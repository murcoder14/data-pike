#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# aws-nuke.sh  —  Delete every AWS resource created by this project.
#
# Reads project_name, environment, and aws_region from a tfvars file so it
# stays in sync with the Terraform config automatically.
#
# Usage:
#   ./terraform/scripts/aws-nuke.sh [path-to-tfvars]
#
# Default tfvars: terraform/terraform.tfvars.dev
#
# WARNING: This is permanently destructive. Run it only in dev/test accounts.
# ---------------------------------------------------------------------------
set -euo pipefail
export AWS_PAGER=""  # never open a pager in non-interactive scripts

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TFVARS_FILE="${1:-$TERRAFORM_DIR/terraform.tfvars.dev}"

if [[ ! -f "$TFVARS_FILE" ]]; then
  echo "ERROR: tfvars file not found: $TFVARS_FILE"
  exit 1
fi

# ---------------------------------------------------------------------------
# Read variables from tfvars
# ---------------------------------------------------------------------------
get_var() {
  grep -E "^${1}\s*=" "$TFVARS_FILE" | sed -E 's/^[^=]+=\s*"(.*)"\s*$/\1/' | tail -1
}

PROJECT=$(get_var project_name)
ENV=$(get_var environment)
REGION=$(get_var aws_region)
REGION="${REGION:-us-east-1}"

INPUT_BUCKET=$(get_var input_bucket_name)
INPUT_BUCKET="${INPUT_BUCKET:-${PROJECT}-input-${ENV}}"
ICEBERG_BUCKET=$(get_var iceberg_bucket_name)
ICEBERG_BUCKET="${ICEBERG_BUCKET:-${PROJECT}-output-${ENV}}"
JAR_BUCKET=$(get_var jar_bucket_name)
JAR_BUCKET="${JAR_BUCKET:-${PROJECT}-jar-${ENV}}"
ARTIFACTS_BUCKET=$(get_var pipeline_artifacts_bucket_name)
ARTIFACTS_BUCKET="${ARTIFACTS_BUCKET:-${PROJECT}-pipeline-artifacts-${ENV}}"
STATE_BUCKET="${PROJECT}-tf-state"

KINESIS_STREAM=$(get_var kinesis_stream_name)
KINESIS_STREAM="${KINESIS_STREAM:-${PROJECT}-${ENV}}"
GLUE_DB=$(get_var iceberg_database_name)
GLUE_DB="${GLUE_DB:-flink_pipeline}"

KMS_ALIAS="alias/${PROJECT}-${ENV}"
FLINK_APP="${PROJECT}-${ENV}"
DYNAMO_TABLE="${PROJECT}-tf-lock"

echo "========================================================"
echo "  aws-nuke: ${PROJECT}-${ENV}  region=${REGION}"
echo "========================================================"
echo "This will PERMANENTLY DELETE all AWS resources for this project."
read -rp "Type 'yes' to continue: " CONFIRM
[[ "$CONFIRM" == "yes" ]] || { echo "Aborted."; exit 0; }

AWS="aws --region $REGION"

# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------
delete_s3_bucket() {
  local bucket="$1"
  echo "--- S3: emptying and deleting $bucket"
  if $AWS s3api head-bucket --bucket "$bucket" 2>/dev/null; then
    # Delete all object versions and delete markers (handles versioned buckets)
    $AWS s3api list-object-versions --bucket "$bucket" \
      --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
      --output json 2>/dev/null | \
      python3 -c "
import json, sys
data = json.load(sys.stdin)
objects = data.get('Objects') or []
if objects:
    print(json.dumps({'Objects': objects, 'Quiet': True}))
" | grep -q '.' && \
    $AWS s3api delete-objects --bucket "$bucket" \
      --delete "$(
        $AWS s3api list-object-versions --bucket "$bucket" \
          --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
          --output json | python3 -c "
import json,sys; d=json.load(sys.stdin); objs=d.get('Objects') or []
print(json.dumps({'Objects':objs,'Quiet':True})) if objs else print('{\"Objects\":[]}')
")" 2>/dev/null || true

    $AWS s3api list-object-versions --bucket "$bucket" \
      --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
      --output json 2>/dev/null | \
      python3 -c "
import json, sys
data = json.load(sys.stdin)
objects = data.get('Objects') or []
if objects:
    print(json.dumps({'Objects': objects, 'Quiet': True}))
" | grep -q '.' && \
    $AWS s3api delete-objects --bucket "$bucket" \
      --delete "$(
        $AWS s3api list-object-versions --bucket "$bucket" \
          --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
          --output json | python3 -c "
import json,sys; d=json.load(sys.stdin); objs=d.get('Objects') or []
print(json.dumps({'Objects':objs,'Quiet':True})) if objs else print('{\"Objects\":[]}')
")" 2>/dev/null || true

    $AWS s3 rm "s3://$bucket" --recursive 2>/dev/null || true
    $AWS s3api delete-bucket --bucket "$bucket" && echo "  Deleted $bucket" || echo "  Could not delete $bucket (may already be gone)"
  else
    echo "  Skipping $bucket (does not exist)"
  fi
}

# ---------------------------------------------------------------------------
# 1. Flink application
# ---------------------------------------------------------------------------
echo ""
echo "=== Flink application ==="
if $AWS kinesisanalyticsv2 describe-application --application-name "$FLINK_APP" \
    --query 'ApplicationDetail.ApplicationStatus' --output text 2>/dev/null | grep -qE "RUNNING|STARTING|UPDATING"; then
  echo "--- Stopping Flink app $FLINK_APP"
  $AWS kinesisanalyticsv2 stop-application \
    --application-name "$FLINK_APP" --force 2>/dev/null || true
  echo "    Waiting for app to stop..."
  for i in $(seq 1 30); do
    STATUS=$($AWS kinesisanalyticsv2 describe-application --application-name "$FLINK_APP" \
      --query 'ApplicationDetail.ApplicationStatus' --output text 2>/dev/null || echo "DELETED")
    [[ "$STATUS" == "READY" || "$STATUS" == "DELETED" ]] && break
    sleep 5
  done
fi
echo "--- Deleting Flink app $FLINK_APP"
$AWS kinesisanalyticsv2 delete-application \
  --application-name "$FLINK_APP" \
  --create-timestamp "$(
    $AWS kinesisanalyticsv2 describe-application --application-name "$FLINK_APP" \
      --query 'ApplicationDetail.CreateTimestamp' --output text 2>/dev/null || echo ""
  )" 2>/dev/null && echo "  Deleted $FLINK_APP" || echo "  Skipping (not found)"

# ---------------------------------------------------------------------------
# 2. CodePipeline
# ---------------------------------------------------------------------------
echo ""
echo "=== CodePipeline ==="
PIPELINE_NAME="${PROJECT}-${ENV}"
$AWS codepipeline delete-pipeline --name "$PIPELINE_NAME" 2>/dev/null && \
  echo "  Deleted pipeline $PIPELINE_NAME" || echo "  Skipping $PIPELINE_NAME (not found)"

# ---------------------------------------------------------------------------
# 3. CodeBuild projects
# ---------------------------------------------------------------------------
echo ""
echo "=== CodeBuild projects ==="
for stage in build plan apply; do
  CB="${PROJECT}-${ENV}-${stage}"
  $AWS codebuild delete-project --name "$CB" 2>/dev/null && \
    echo "  Deleted $CB" || echo "  Skipping $CB (not found)"
done

# ---------------------------------------------------------------------------
# 4. CodeConnections / CodeStar connection
# ---------------------------------------------------------------------------
echo ""
echo "=== CodeConnections ==="
CONN_ARNS=$($AWS codeconnections list-connections \
  --query "Connections[?contains(ConnectionName,'${PROJECT}')].ConnectionArn" \
  --output text 2>/dev/null || \
  $AWS codestar-connections list-connections \
  --query "Connections[?contains(ConnectionName,'${PROJECT}')].ConnectionArn" \
  --output text 2>/dev/null || true)
for arn in $CONN_ARNS; do
  $AWS codeconnections delete-connection --connection-arn "$arn" 2>/dev/null || \
  $AWS codestar-connections delete-connection --connection-arn "$arn" 2>/dev/null || true
  echo "  Deleted connection $arn"
done

# ---------------------------------------------------------------------------
# 5. EventBridge rule
# ---------------------------------------------------------------------------
echo ""
echo "=== EventBridge ==="
EB_RULE="${PROJECT}-${ENV}-s3-object-created"
$AWS events remove-targets --rule "$EB_RULE" --ids kinesis-stream 2>/dev/null || true
$AWS events delete-rule --name "$EB_RULE" 2>/dev/null && \
  echo "  Deleted EventBridge rule $EB_RULE" || echo "  Skipping $EB_RULE (not found)"

# ---------------------------------------------------------------------------
# 6. Kinesis stream
# ---------------------------------------------------------------------------
echo ""
echo "=== Kinesis ==="
$AWS kinesis delete-stream --stream-name "$KINESIS_STREAM" --enforce-consumer-deletion 2>/dev/null && \
  echo "  Deleted stream $KINESIS_STREAM" || echo "  Skipping $KINESIS_STREAM (not found)"

# ---------------------------------------------------------------------------
# 7. CloudWatch log groups
# ---------------------------------------------------------------------------
echo ""
echo "=== CloudWatch log groups ==="
for lg in \
  "/aws/kinesis-analytics/${PROJECT}-${ENV}" \
  "/aws/codebuild/${PROJECT}-${ENV}-build" \
  "/aws/codebuild/${PROJECT}-${ENV}-plan" \
  "/aws/codebuild/${PROJECT}-${ENV}-apply" \
  "/aws/vpc/flowlogs/${PROJECT}-${ENV}"; do
  $AWS logs delete-log-group --log-group-name "$lg" 2>/dev/null && \
    echo "  Deleted $lg" || echo "  Skipping $lg (not found)"
done

# ---------------------------------------------------------------------------
# 8. IAM roles and inline policies
# ---------------------------------------------------------------------------
echo ""
echo "=== IAM roles ==="
for role in \
  "${PROJECT}-${ENV}-flink-execution" \
  "${PROJECT}-${ENV}-codebuild-build" \
  "${PROJECT}-${ENV}-codebuild-plan" \
  "${PROJECT}-${ENV}-codebuild-apply" \
  "${PROJECT}-${ENV}-codepipeline" \
  "${PROJECT}-${ENV}-eventbridge-kinesis" \
  "${PROJECT}-${ENV}-vpc-flow-logs"; do
  if aws iam get-role --role-name "$role" --query 'Role.RoleName' --output text 2>/dev/null | grep -q .; then
    # Detach managed policies
    ATTACHED=$(aws iam list-attached-role-policies --role-name "$role" \
      --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || true)
    for p in $ATTACHED; do
      aws iam detach-role-policy --role-name "$role" --policy-arn "$p" 2>/dev/null || true
    done
    # Delete inline policies
    INLINE=$(aws iam list-role-policies --role-name "$role" \
      --query 'PolicyNames[]' --output text 2>/dev/null || true)
    for p in $INLINE; do
      aws iam delete-role-policy --role-name "$role" --policy-name "$p" 2>/dev/null || true
    done
    aws iam delete-role --role-name "$role" && echo "  Deleted role $role" || true
  else
    echo "  Skipping $role (not found)"
  fi
done

# ---------------------------------------------------------------------------
# 9. Glue database
# ---------------------------------------------------------------------------
echo ""
echo "=== Glue catalog ==="
$AWS glue delete-database --name "$GLUE_DB" 2>/dev/null && \
  echo "  Deleted Glue database $GLUE_DB" || echo "  Skipping $GLUE_DB (not found)"

# ---------------------------------------------------------------------------
# 10. VPC and networking
# ---------------------------------------------------------------------------
echo ""
echo "=== VPC and networking ==="
VPC_ID=$($AWS ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=${PROJECT}-${ENV}" \
  --query 'Vpcs[0].VpcId' --output text 2>/dev/null || true)

if [[ -n "$VPC_ID" && "$VPC_ID" != "None" ]]; then
  echo "--- Found VPC $VPC_ID — deleting dependencies first"

  # VPC endpoints
  ENDPOINT_IDS=$($AWS ec2 describe-vpc-endpoints \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'VpcEndpoints[].VpcEndpointId' --output text 2>/dev/null || true)
  [[ -n "$ENDPOINT_IDS" ]] && \
    $AWS ec2 delete-vpc-endpoints --vpc-endpoint-ids $ENDPOINT_IDS 2>/dev/null || true

  # Security groups (skip default)
  SG_IDS=$($AWS ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text 2>/dev/null || true)
  for sg in $SG_IDS; do
    $AWS ec2 delete-security-group --group-id "$sg" 2>/dev/null || true
    echo "  Deleted security group $sg"
  done

  # Subnets
  SUBNET_IDS=$($AWS ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'Subnets[].SubnetId' --output text 2>/dev/null || true)
  for subnet in $SUBNET_IDS; do
    $AWS ec2 delete-subnet --subnet-id "$subnet" 2>/dev/null || true
    echo "  Deleted subnet $subnet"
  done

  # Route tables (skip main)
  RT_IDS=$($AWS ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'RouteTables[?Associations[?Main==`false`]||!Associations].RouteTableId' \
    --output text 2>/dev/null || true)
  for rt in $RT_IDS; do
    $AWS ec2 delete-route-table --route-table-id "$rt" 2>/dev/null || true
    echo "  Deleted route table $rt"
  done

  # Internet gateways
  IGW_IDS=$($AWS ec2 describe-internet-gateways \
    --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
    --query 'InternetGateways[].InternetGatewayId' --output text 2>/dev/null || true)
  for igw in $IGW_IDS; do
    $AWS ec2 detach-internet-gateway --internet-gateway-id "$igw" --vpc-id "$VPC_ID" 2>/dev/null || true
    $AWS ec2 delete-internet-gateway --internet-gateway-id "$igw" 2>/dev/null || true
    echo "  Deleted IGW $igw"
  done

  $AWS ec2 delete-vpc --vpc-id "$VPC_ID" && echo "  Deleted VPC $VPC_ID" || \
    echo "  Could not delete VPC $VPC_ID — may have remaining dependencies"
else
  echo "  No VPC found for ${PROJECT}-${ENV}"
fi

# ---------------------------------------------------------------------------
# 11. S3 buckets
# ---------------------------------------------------------------------------
echo ""
echo "=== S3 buckets ==="
for bucket in "$INPUT_BUCKET" "$ICEBERG_BUCKET" "$JAR_BUCKET" "$ARTIFACTS_BUCKET"; do
  delete_s3_bucket "$bucket"
done

# ---------------------------------------------------------------------------
# 12. KMS alias and key
# ---------------------------------------------------------------------------
echo ""
echo "=== KMS ==="
echo "--- Deleting alias $KMS_ALIAS"
KEY_ID=$($AWS kms describe-key --key-id "$KMS_ALIAS" \
  --query 'KeyMetadata.KeyId' --output text 2>/dev/null || true)

$AWS kms delete-alias --alias-name "$KMS_ALIAS" 2>/dev/null && \
  echo "  Deleted alias $KMS_ALIAS" || echo "  Skipping alias (not found)"

if [[ -n "$KEY_ID" ]]; then
  STATE=$($AWS kms describe-key --key-id "$KEY_ID" \
    --query 'KeyMetadata.KeyState' --output text 2>/dev/null || true)
  if [[ "$STATE" == "Enabled" || "$STATE" == "Disabled" ]]; then
    $AWS kms schedule-key-deletion --key-id "$KEY_ID" --pending-window-in-days 7 && \
      echo "  Scheduled key $KEY_ID for deletion in 7 days (AWS minimum)" || true
  else
    echo "  Key $KEY_ID already in state: $STATE — skipping"
  fi
fi

# ---------------------------------------------------------------------------
# 13. Terraform state bucket and DynamoDB lock table
# ---------------------------------------------------------------------------
echo ""
echo "=== Terraform state backend ==="
echo "  State bucket : ${STATE_BUCKET}"
echo "  DynamoDB table: ${DYNAMO_TABLE}"
echo "  WARNING: Deleting these means all Terraform state history is gone forever."
read -rp "  Delete the state bucket and DynamoDB lock table? [yes/NO] " NUKE_STATE
if [[ "${NUKE_STATE,,}" == "yes" ]]; then
  delete_s3_bucket "$STATE_BUCKET"
  $AWS dynamodb delete-table --table-name "$DYNAMO_TABLE" 2>/dev/null && \
    echo "  Deleted DynamoDB table $DYNAMO_TABLE" || echo "  Skipping $DYNAMO_TABLE (not found)"
else
  echo "  Skipped — state backend left intact."
fi

# ---------------------------------------------------------------------------
# 14. Wipe local Terraform state
# ---------------------------------------------------------------------------
echo ""
echo "=== Local Terraform state ==="
cd "$TERRAFORM_DIR"
[[ -f backend.tf.disabled && ! -f backend.tf ]] && mv backend.tf.disabled backend.tf && echo "  Restored backend.tf"
rm -rf .terraform .terraform.lock.hcl terraform.tfstate terraform.tfstate.backup tfplan
echo "  Cleared .terraform/, lock file, and local state files"

echo ""
echo "========================================================"
echo "  Cleanup complete."
echo "  NOTE: KMS key deletion has a 7-day mandatory wait."
echo "  Re-deploying before 7 days: a new key + alias will be"
echo "  created automatically — no action needed."
echo "========================================================"
