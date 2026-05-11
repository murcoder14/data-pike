#!/usr/bin/env bash
set -euo pipefail

# One-shot dev workflow:
# 1) tf-apply.sh: state sync, storage bootstrap, build+upload JAR, full apply
# 2) Ensure Flink app is RUNNING
# 3) Run JSON/XML smoke upload

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

DEV_TFVARS="$TERRAFORM_DIR/terraform.tfvars.dev"

[[ -f "$DEV_TFVARS" ]] || { echo "Missing $DEV_TFVARS"; exit 1; }
command -v terraform >/dev/null || { echo "terraform is required on PATH"; exit 1; }
command -v aws       >/dev/null || { echo "aws CLI is required on PATH"; exit 1; }

cd "$TERRAFORM_DIR"

echo "==> Running tf-apply.sh dev (state sync + build + upload + apply)..."
bash "$SCRIPT_DIR/tf-apply.sh" dev

FLINK_APP_NAME="$(terraform output -raw flink_application_name)"

STATUS="$(aws kinesisanalyticsv2 describe-application \
  --application-name "$FLINK_APP_NAME" \
  --query 'ApplicationDetail.ApplicationStatus' \
  --output text)"

if [[ "$STATUS" != "RUNNING" ]]; then
  echo "Flink app status is $STATUS, attempting start..."
  aws kinesisanalyticsv2 start-application \
    --application-name "$FLINK_APP_NAME" \
    --run-configuration '{}'
fi

echo "==> Running dev smoke test (upload JSON/XML)..."
"$SCRIPT_DIR/dev-smoke-test.sh"

echo
LOG_GROUP="$(terraform output -raw flink_log_group_name 2>/dev/null || true)"
[[ -n "$LOG_GROUP" ]] && echo "Tail logs: aws logs tail '${LOG_GROUP}' --since 20m --follow"
echo "Dev deploy + smoke complete."
