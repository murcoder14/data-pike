#!/usr/bin/env bash
set -euo pipefail

# Bootstraps Terraform remote state resources when backend "s3" is configured.
# Works around Terraform behavior that blocks apply when backend is declared but not initialized.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

BACKEND_FILE="$TERRAFORM_DIR/backend.tf"
BACKEND_DISABLED_FILE="$TERRAFORM_DIR/backend.tf.disabled"
TFVARS_FILE="${1:-$TERRAFORM_DIR/terraform.tfvars.dev}"

if [[ -f "$BACKEND_DISABLED_FILE" && ! -f "$BACKEND_FILE" ]]; then
  echo "Recovering backend.tf from a previous interrupted run..."
  mv "$BACKEND_DISABLED_FILE" "$BACKEND_FILE"
fi

if [[ ! -f "$BACKEND_FILE" ]]; then
  echo "Missing $BACKEND_FILE"
  exit 1
fi

PROJECT_NAME=""
AWS_REGION="us-east-1"
if [[ -f "$TFVARS_FILE" ]]; then
  PROJECT_NAME="$(grep -E '^project_name\s*=' "$TFVARS_FILE" | sed -E 's/^[^=]+=\s*"(.*)"\s*$/\1/' | tail -1)"
  AWS_REGION_RAW="$(grep -E '^aws_region\s*=' "$TFVARS_FILE" | sed -E 's/^[^=]+=\s*"(.*)"\s*$/\1/' | tail -1)"
  if [[ -n "$AWS_REGION_RAW" ]]; then
    AWS_REGION="$AWS_REGION_RAW"
  fi
fi

if [[ -z "$PROJECT_NAME" ]]; then
  echo "Could not determine project_name from $TFVARS_FILE"
  echo "Pass a tfvars file containing project_name as first argument."
  exit 1
fi

cleanup() {
  if [[ -f "$BACKEND_DISABLED_FILE" && ! -f "$BACKEND_FILE" ]]; then
    mv "$BACKEND_DISABLED_FILE" "$BACKEND_FILE"
  fi
}
trap cleanup EXIT

cd "$TERRAFORM_DIR"

echo "Temporarily disabling backend config..."
mv "$BACKEND_FILE" "$BACKEND_DISABLED_FILE"

echo "Clearing any cached backend state from previous runs..."
rm -rf .terraform .terraform.lock.hcl terraform.tfstate terraform.tfstate.backup

echo "Initializing with local state for bootstrap..."
terraform init -reconfigure -backend=false -input=false

echo "Creating state bucket and lock table resources..."
terraform apply -input=false -auto-approve -var-file="$TFVARS_FILE" \
  -target=aws_s3_bucket.terraform_state \
  -target=aws_s3_bucket_versioning.terraform_state \
  -target=aws_s3_bucket_server_side_encryption_configuration.terraform_state \
  -target=aws_s3_bucket_public_access_block.terraform_state \
  -target=aws_dynamodb_table.terraform_lock

echo "Restoring backend config..."
mv "$BACKEND_DISABLED_FILE" "$BACKEND_FILE"

echo "Re-initializing S3 backend..."
terraform init -reconfigure \
  -backend-config="bucket=${PROJECT_NAME}-tf-state" \
  -backend-config="key=${PROJECT_NAME}/dev/terraform.tfstate" \
  -backend-config="region=${AWS_REGION}" \
  -backend-config="use_lockfile=true" \
  -backend-config="encrypt=true"

echo "Bootstrap complete."
