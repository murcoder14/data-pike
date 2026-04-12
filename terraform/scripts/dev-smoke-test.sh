#!/usr/bin/env bash
set -euo pipefail

# Dev smoke test for the data-pike pipeline.
# 1) Resolves Terraform outputs
# 2) Uploads sample JSON and XML files to the input bucket
# 3) Prints CloudWatch and table inspection commands

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$TERRAFORM_DIR/.." && pwd)"

cd "$TERRAFORM_DIR"

if ! command -v terraform >/dev/null 2>&1; then
  echo "terraform is required on PATH"
  exit 1
fi

if ! command -v aws >/dev/null 2>&1; then
  echo "aws cli is required on PATH"
  exit 1
fi

INPUT_BUCKET="$(terraform output -raw input_bucket_name)"
FLINK_APP_NAME="$(terraform output -raw flink_application_name)"
FLINK_LOG_GROUP="$(terraform output -raw flink_log_group_name)"
GLUE_DB="$(terraform output -raw glue_database_name)"
GLUE_TABLE="$(terraform output -raw glue_table_name)"

JSON_SRC="$REPO_ROOT/src/test/resources/weather_data.json"
XML_SRC="$REPO_ROOT/src/test/resources/weather_data.xml"

if [[ ! -f "$JSON_SRC" || ! -f "$XML_SRC" ]]; then
  echo "sample files missing under src/test/resources"
  exit 1
fi

TS="$(date +%Y%m%d-%H%M%S)"
JSON_KEY="smoke/weather_data-${TS}.json"
XML_KEY="smoke/weather_data-${TS}.xml"

echo "Uploading sample JSON/XML to s3://$INPUT_BUCKET ..."
aws s3 cp "$JSON_SRC" "s3://$INPUT_BUCKET/$JSON_KEY"
aws s3 cp "$XML_SRC" "s3://$INPUT_BUCKET/$XML_KEY"

echo
cat <<EOF
Smoke test uploads complete.

Flink application:
  $FLINK_APP_NAME

Uploaded objects:
  s3://$INPUT_BUCKET/$JSON_KEY
  s3://$INPUT_BUCKET/$XML_KEY

Check Flink status:
  aws kinesisanalyticsv2 describe-application --application-name "$FLINK_APP_NAME" --query 'ApplicationDetail.ApplicationStatus' --output text

Tail Flink logs (last 20 minutes):
  aws logs tail "$FLINK_LOG_GROUP" --since 20m --follow

Query Iceberg table (Athena engine 3, example):
  SELECT *
  FROM "$GLUE_DB"."$GLUE_TABLE"
  ORDER BY date;

If rows are missing, validate EventBridge -> Kinesis flow:
  aws events list-rule-names-by-target --target-arn "$(terraform output -raw kinesis_stream_arn)"
EOF
