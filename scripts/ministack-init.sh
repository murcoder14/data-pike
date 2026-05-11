#!/usr/bin/env bash
# ministack-init.sh
# Pre-creates AWS resources in MiniStack that the Flink pipeline depends on.
# Run once after MiniStack is healthy, before submitting the Flink job.
#
# Required env vars (with defaults):
#   MINISTACK_ENDPOINT  — MiniStack HTTP endpoint (default: http://localhost:4566)
#   STREAM_NAME         — Kinesis stream name (default: weather-stream)
#   INPUT_BUCKET        — S3 bucket for incoming data files (default: data-pike-input)
#   AWS_REGION          — AWS region (default: us-east-1)
set -euo pipefail

ENDPOINT="${MINISTACK_ENDPOINT:-http://localhost:4566}"
STREAM_NAME="${STREAM_NAME:-weather-stream}"
INPUT_BUCKET="${INPUT_BUCKET:-data-pike-input}"
REGION="${AWS_REGION:-us-east-1}"
ACCOUNT_ID="000000000000"

AWS="aws --endpoint-url ${ENDPOINT} --region ${REGION}"

echo "Initialising MiniStack resources (endpoint=${ENDPOINT})..."

# ---------------------------------------------------------------------------
# 1. Kinesis stream
# ---------------------------------------------------------------------------
if ${AWS} kinesis describe-stream-summary --stream-name "${STREAM_NAME}" \
    --query 'StreamDescriptionSummary.StreamStatus' --output text 2>/dev/null | grep -qE "ACTIVE|CREATING"; then
  echo "  Kinesis stream '${STREAM_NAME}' already exists — skipping."
else
  echo "  Creating Kinesis stream '${STREAM_NAME}'..."
  ${AWS} kinesis create-stream --stream-name "${STREAM_NAME}" --shard-count 1
  echo "  Waiting for stream to become ACTIVE..."
  for _ in $(seq 1 30); do
    STATUS=$(${AWS} kinesis describe-stream-summary --stream-name "${STREAM_NAME}" \
        --query 'StreamDescriptionSummary.StreamStatus' --output text 2>/dev/null || true)
    [[ "${STATUS}" == "ACTIVE" ]] && break
    sleep 1
  done
  echo "  Kinesis stream '${STREAM_NAME}' is ACTIVE."
fi

STREAM_ARN="${AWS_ACCOUNT_ARN:-arn:aws:kinesis:${REGION}:${ACCOUNT_ID}:stream/${STREAM_NAME}}"

# ---------------------------------------------------------------------------
# 2. S3 input bucket
# ---------------------------------------------------------------------------
if ${AWS} s3api head-bucket --bucket "${INPUT_BUCKET}" 2>/dev/null; then
  echo "  S3 bucket 's3://${INPUT_BUCKET}' already exists — skipping."
else
  echo "  Creating S3 bucket 's3://${INPUT_BUCKET}'..."
  ${AWS} s3 mb "s3://${INPUT_BUCKET}"
fi

echo ""
echo "MiniStack initialisation complete."
echo "  Stream ARN : ${STREAM_ARN}"
echo "  Input bucket: s3://${INPUT_BUCKET}"
echo "  Publish scripts upload to S3 and put S3 notifications directly into Kinesis."
echo "  (MiniStack EventBridge→Kinesis target routing is not used.)"
