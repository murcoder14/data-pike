#!/usr/bin/env bash
set -euo pipefail

# One-shot dev workflow:
# 1) terraform apply (storage only) so JAR bucket exists
# 2) mvn package
# 3) upload JAR to configured file_key
# 4) terraform apply full stack (creates/updates Flink app)
# 5) ensure Flink app is RUNNING
# 6) run JSON/XML smoke upload + verification hints

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$TERRAFORM_DIR/.." && pwd)"

DEV_TFVARS="$TERRAFORM_DIR/terraform.tfvars.dev"

if [[ ! -f "$DEV_TFVARS" ]]; then
  echo "Missing $DEV_TFVARS"
  exit 1
fi

if ! command -v terraform >/dev/null 2>&1; then
  echo "terraform is required on PATH"
  exit 1
fi

if ! command -v aws >/dev/null 2>&1; then
  echo "aws cli is required on PATH"
  exit 1
fi

if ! command -v mvn >/dev/null 2>&1; then
  echo "maven (mvn) is required on PATH"
  exit 1
fi

cd "$TERRAFORM_DIR"

echo "Applying Terraform (dev, storage bootstrap for JAR bucket)..."
terraform apply -input=false -auto-approve -var-file=terraform.tfvars.dev -target=module.storage

JAR_BUCKET="$(terraform output -raw jar_bucket_name)"
FLINK_APP_NAME="$(terraform output -raw flink_application_name)"

FILE_KEY="$(grep -E '^file_key\s*=' "$DEV_TFVARS" | sed -E 's/^[^=]+=\s*"(.*)"\s*$/\1/' | tail -1)"
if [[ -z "$FILE_KEY" ]]; then
  echo "Could not parse file_key from $DEV_TFVARS"
  exit 1
fi

cd "$REPO_ROOT"

echo "Building application JAR..."
mvn clean package -DskipTests

JAR_FILE="$(find target -maxdepth 1 -name '*.jar' -not -name 'original-*' | head -1)"
if [[ -z "$JAR_FILE" ]]; then
  echo "No built JAR found under target/"
  exit 1
fi

echo "Uploading JAR to s3://$JAR_BUCKET/$FILE_KEY ..."
aws s3 cp "$JAR_FILE" "s3://$JAR_BUCKET/$FILE_KEY"

cd "$TERRAFORM_DIR"
echo "Applying Terraform (dev, full stack)..."
terraform apply -input=false -auto-approve -var-file=terraform.tfvars.dev

STATUS="$(aws kinesisanalyticsv2 describe-application --application-name "$FLINK_APP_NAME" --query 'ApplicationDetail.ApplicationStatus' --output text)"
if [[ "$STATUS" != "RUNNING" ]]; then
  echo "Flink app status is $STATUS, attempting start..."
  aws kinesisanalyticsv2 start-application \
    --application-name "$FLINK_APP_NAME" \
    --run-configuration '{}'
fi

echo "Running dev smoke test (upload JSON/XML)..."
"$SCRIPT_DIR/dev-smoke-test.sh"

echo
cat <<EOF
Dev deploy + smoke workflow complete.
If needed, tail logs with:
  aws logs tail "$(cd "$TERRAFORM_DIR" && terraform output -raw flink_log_group_name)" --since 20m --follow
EOF
