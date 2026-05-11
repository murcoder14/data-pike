#!/usr/bin/env bash
# =============================================================================
# tf-apply.sh — Idempotent Terraform apply for any environment.
#
# Handles state drift that accumulates across destroy/recreate cycles:
#   - Detects AWS resources that exist but are absent from Terraform state
#   - Imports them so Terraform won't error with "already exists"
#   - Handles the KMS alias edge case (alias pointing to a pending-deletion key)
#   - Safe to run repeatedly; skips resources already tracked in state
#
# Usage:
#   ./scripts/tf-apply.sh [dev|prod]      # auto-approve
#   ./scripts/tf-apply.sh dev --no-apply  # sync state only, skip apply
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${TERRAFORM_DIR}"

ENV="${1:-dev}"
SKIP_APPLY=false
for arg in "$@"; do [[ "${arg}" == "--no-apply" ]] && SKIP_APPLY=true; done

TFVARS="terraform.tfvars.${ENV}"
[[ -f "${TFVARS}" ]] || { echo "ERROR: ${TFVARS} not found"; exit 1; }
command -v terraform >/dev/null || { echo "ERROR: terraform not on PATH"; exit 1; }
command -v aws       >/dev/null || { echo "ERROR: aws CLI not on PATH"; exit 1; }

# =============================================================================
# Parse tfvars
# =============================================================================

get_var() {
  # Handles: key = "value" and key = "value" # comment
  grep -E "^${1}\s*=" "${TFVARS}" \
    | sed -E 's/^[^=]+=\s*"([^"]*)"\s*(#.*)?$/\1/' \
    | tail -1
}

PROJECT="${TF_VAR_project_name:-$(get_var project_name)}"
ENVIRONMENT="${TF_VAR_environment:-$(get_var environment)}"
REGION="${TF_VAR_aws_region:-$(get_var aws_region)}"
KINESIS_STREAM="${TF_VAR_kinesis_stream_name:-$(get_var kinesis_stream_name)}"
INPUT_BUCKET="${TF_VAR_input_bucket_name:-$(get_var input_bucket_name)}"
ICEBERG_BUCKET="${TF_VAR_iceberg_bucket_name:-$(get_var iceberg_bucket_name)}"
JAR_BUCKET="${TF_VAR_jar_bucket_name:-$(get_var jar_bucket_name)}"
ICEBERG_DB="${TF_VAR_iceberg_database_name:-$(get_var iceberg_database_name)}"

# Fall back to derived names for optional variables
[[ -z "${KINESIS_STREAM}" ]] && KINESIS_STREAM="${PROJECT}-${ENVIRONMENT}"
[[ -z "${INPUT_BUCKET}"   ]] && INPUT_BUCKET="${PROJECT}-${ENVIRONMENT}-input"
[[ -z "${ICEBERG_BUCKET}" ]] && ICEBERG_BUCKET="${PROJECT}-${ENVIRONMENT}-output"
[[ -z "${JAR_BUCKET}"     ]] && JAR_BUCKET="${PROJECT}-${ENVIRONMENT}-jar"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

# Derived resource names (must match the naming patterns in each module)
FLINK_ROLE="${PROJECT}-${ENVIRONMENT}-flink-execution"
EVENTBRIDGE_ROLE="${PROJECT}-${ENVIRONMENT}-eventbridge-kinesis"
KMS_ALIAS_NAME="alias/${PROJECT}-${ENVIRONMENT}"
FLINK_APP_NAME="${PROJECT}-${ENVIRONMENT}"
LOG_GROUP_NAME="/aws/kinesis-analytics/${PROJECT}-${ENVIRONMENT}"

# =============================================================================
# Helpers
# =============================================================================

in_state() {
  terraform state show "$1" &>/dev/null
}

# Import addr if it exists in AWS (check_cmd must exit 0 when resource exists)
try_import() {
  local addr="$1"
  local aws_id="$2"
  local check_cmd="$3"

  if in_state "${addr}"; then
    printf "  [ok]     %s\n" "${addr}"
    return 0
  fi

  if eval "${check_cmd}" &>/dev/null; then
    printf "  [import] %s\n" "${addr}"
    terraform import -var-file="${TFVARS}" "${addr}" "${aws_id}" \
      || printf "  [warn]   import failed for %s — continuing\n" "${addr}"
  else
    printf "  [absent] %s — will be created by apply\n" "${addr}"
  fi
}

# =============================================================================
# Step 1: State sync
# =============================================================================

echo ""
echo "==> Syncing Terraform state with AWS (${ENV}) ..."
echo ""

# --- KMS Alias (special case) ---
# The alias may point to a pending-deletion key from a previous destroy cycle.
# Importing a pending-deletion alias would break the apply, so delete it instead.
if ! in_state "module.storage.aws_kms_alias.encryption"; then
  TARGET_KEY_ID="$(aws kms list-aliases \
    --region "${REGION}" \
    --query "Aliases[?AliasName=='${KMS_ALIAS_NAME}'].TargetKeyId" \
    --output text 2>/dev/null || true)"

  if [[ -n "${TARGET_KEY_ID}" && "${TARGET_KEY_ID}" != "None" ]]; then
    KEY_STATE="$(aws kms describe-key \
      --key-id "${TARGET_KEY_ID}" \
      --region "${REGION}" \
      --query 'KeyMetadata.KeyState' \
      --output text 2>/dev/null || true)"

    if [[ "${KEY_STATE}" == "PendingDeletion" ]]; then
      echo "  [fix]    KMS alias ${KMS_ALIAS_NAME} points to a pending-deletion key — deleting alias so apply can create a fresh one"
      aws kms delete-alias --alias-name "${KMS_ALIAS_NAME}" --region "${REGION}"
    else
      printf "  [import] module.storage.aws_kms_alias.encryption\n"
      terraform import -var-file="${TFVARS}" \
        module.storage.aws_kms_alias.encryption "${KMS_ALIAS_NAME}" \
        || printf "  [warn]   KMS alias import failed — continuing\n"
    fi
  else
    printf "  [absent] module.storage.aws_kms_alias.encryption — will be created by apply\n"
  fi
else
  printf "  [ok]     module.storage.aws_kms_alias.encryption\n"
fi

# --- IAM Roles ---
try_import \
  "module.flink.aws_iam_role.flink_execution" \
  "${FLINK_ROLE}" \
  "aws iam get-role --role-name '${FLINK_ROLE}'"

try_import \
  "module.kinesis.aws_iam_role.eventbridge_kinesis" \
  "${EVENTBRIDGE_ROLE}" \
  "aws iam get-role --role-name '${EVENTBRIDGE_ROLE}'"

# --- Glue Catalog Database ---
try_import \
  "module.storage.aws_glue_catalog_database.iceberg" \
  "${ACCOUNT_ID}:${ICEBERG_DB}" \
  "aws glue get-database --name '${ICEBERG_DB}' --region '${REGION}'"

# --- S3 Buckets ---
try_import \
  "module.storage.aws_s3_bucket.input" \
  "${INPUT_BUCKET}" \
  "aws s3api head-bucket --bucket '${INPUT_BUCKET}'"

try_import \
  "module.storage.aws_s3_bucket.iceberg" \
  "${ICEBERG_BUCKET}" \
  "aws s3api head-bucket --bucket '${ICEBERG_BUCKET}'"

try_import \
  "module.storage.aws_s3_bucket.jar" \
  "${JAR_BUCKET}" \
  "aws s3api head-bucket --bucket '${JAR_BUCKET}'"

# --- Kinesis Stream ---
try_import \
  "module.kinesis.aws_kinesis_stream.main" \
  "${KINESIS_STREAM}" \
  "aws kinesis describe-stream-summary --stream-name '${KINESIS_STREAM}' --region '${REGION}'"

# --- CloudWatch Log Group ---
try_import \
  "module.monitoring.aws_cloudwatch_log_group.flink" \
  "${LOG_GROUP_NAME}" \
  "aws logs describe-log-groups --log-group-name-prefix '${LOG_GROUP_NAME}' --region '${REGION}' --query 'logGroups[?logGroupName==\`${LOG_GROUP_NAME}\`] | [0]' --output text | grep -v None"

# --- Flink Application ---
try_import \
  "module.flink.aws_kinesisanalyticsv2_application.flink" \
  "${FLINK_APP_NAME}" \
  "aws kinesisanalyticsv2 describe-application --application-name '${FLINK_APP_NAME}' --region '${REGION}'"

echo ""
echo "==> State sync complete."

[[ "${SKIP_APPLY}" == "true" ]] && { echo "==> --no-apply set, stopping here."; exit 0; }

# =============================================================================
# Step 2: Bootstrap storage (creates JAR bucket if absent)
# =============================================================================

echo ""
echo "==> Phase 1: applying storage module ..."
terraform apply -input=false -auto-approve -var-file="${TFVARS}" -target=module.storage

# =============================================================================
# Step 3: Ensure the application JAR is in S3 before Flink app is created.
#
# Kinesis Analytics v2 CreateApplication validates that the JAR key exists in
# the bucket at creation time; the call fails immediately with
# InvalidArgumentException if the object is absent.
# =============================================================================

FILE_KEY="$(get_var file_key)"
[[ -z "${FILE_KEY}" ]] && { echo "ERROR: could not parse file_key from ${TFVARS}"; exit 1; }

JAR_EXISTS="$(aws s3api head-object \
  --bucket "${JAR_BUCKET}" \
  --key "${FILE_KEY}" \
  --region "${REGION}" \
  --query 'ContentLength' \
  --output text 2>/dev/null || true)"

if [[ -z "${JAR_EXISTS}" || "${JAR_EXISTS}" == "None" ]]; then
  echo ""
  echo "==> JAR not found at s3://${JAR_BUCKET}/${FILE_KEY} — building and uploading ..."
  REPO_ROOT="$(cd "${TERRAFORM_DIR}/.." && pwd)"
  if ! command -v mvn >/dev/null 2>&1; then
    echo "ERROR: mvn not on PATH. Build the JAR and upload it manually:"
    echo "       aws s3 cp target/data-pike-*.jar s3://${JAR_BUCKET}/${FILE_KEY}"
    exit 1
  fi
  (cd "${REPO_ROOT}" && mvn -q -DskipTests clean package)
  LOCAL_JAR="$(find "${REPO_ROOT}/target" -maxdepth 1 -name '*.jar' ! -name 'original-*' | head -1)"
  [[ -z "${LOCAL_JAR}" ]] && { echo "ERROR: no JAR found under target/"; exit 1; }
  aws s3 cp "${LOCAL_JAR}" "s3://${JAR_BUCKET}/${FILE_KEY}"
  echo "==> JAR uploaded."
else
  echo "==> JAR already present at s3://${JAR_BUCKET}/${FILE_KEY} — skipping build."
fi

# =============================================================================
# Step 4: Full stack apply
# =============================================================================

echo ""
echo "==> Phase 2: applying full stack ..."
terraform apply -input=false -auto-approve -var-file="${TFVARS}"

echo ""
echo "==> terraform apply complete."
