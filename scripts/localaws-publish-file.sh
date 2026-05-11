#!/usr/bin/env bash
# Publishes a local file to the MiniStack S3 input bucket, triggering the
# EventBridge → Kinesis → Flink pipeline just like a real S3 upload in AWS.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_ENV_FILE="${ROOT_DIR}/.env.local"

if [[ -f "${COMPOSE_ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${COMPOSE_ENV_FILE}"
  set +a
fi

ENDPOINT="${MINISTACK_ENDPOINT:-http://localhost:4566}"
INPUT_BUCKET="${INPUT_BUCKET:-data-pike-input}"
REGION="${AWS_REGION:-us-east-1}"
AWS="aws --endpoint-url ${ENDPOINT} --region ${REGION}"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/localaws-publish-file.sh json
  ./scripts/localaws-publish-file.sh xml
  ./scripts/localaws-publish-file.sh csv
  ./scripts/localaws-publish-file.sh tsv
  ./scripts/localaws-publish-file.sh <path-to-file>

Examples:
  ./scripts/localaws-publish-file.sh src/test/resources/weather_data.json
  ./scripts/localaws-publish-file.sh src/test/resources/weather_data.csv
EOF
}

resolve_input_file() {
  local input="$1"
  case "${input}" in
    json) echo "${ROOT_DIR}/src/test/resources/weather_data.json" ;;
    xml)  echo "${ROOT_DIR}/src/test/resources/weather_data.xml"  ;;
    csv)  echo "${ROOT_DIR}/src/test/resources/weather_data.csv"  ;;
    tsv)  echo "${ROOT_DIR}/src/test/resources/weather_data.tsv"  ;;
    *)
      if [[ "${input}" = /* ]]; then
        echo "${input}"
      else
        echo "${ROOT_DIR}/${input}"
      fi
      ;;
  esac
}

if [[ $# -ne 1 ]]; then
  usage
  exit 1
fi

FILE_PATH="$(resolve_input_file "$1")"

if [[ ! -f "${FILE_PATH}" ]]; then
  echo "File not found: ${FILE_PATH}"
  exit 1
fi

if ! command -v aws >/dev/null 2>&1; then
  echo "Missing required command: aws (AWS CLI)"
  exit 1
fi

S3_KEY="data/$(basename "${FILE_PATH}")"

# Ensure the Flink taskmanager container (which runs as a different uid) can
# write Avro data files into the warehouse.  Trino's CREATE SCHEMA creates
# subdirectories owned by the Trino container uid, so we fix permissions here
# before every publish rather than relying solely on the one-time chmod in
# localaws-up.sh.
chmod -R a+rwx "${ROOT_DIR}/local-data/warehouse" 2>/dev/null || true

AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test \
  ${AWS} s3 cp "${FILE_PATH}" "s3://${INPUT_BUCKET}/${S3_KEY}"

# MiniStack does not route EventBridge targets to Kinesis, so we publish
# the S3 Object Created notification directly as a Kinesis record.
# MessageParser reads: detail.bucket.name + detail.object.key
EVENT_JSON="{\"source\":\"aws.s3\",\"detail-type\":\"Object Created\",\"time\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"detail\":{\"bucket\":{\"name\":\"${INPUT_BUCKET}\"},\"object\":{\"key\":\"${S3_KEY}\"}}}"

AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test \
  ${AWS} kinesis put-record \
    --stream-name "${STREAM_NAME:-weather-stream}" \
    --partition-key "${S3_KEY}" \
    --data "$(printf '%s' "${EVENT_JSON}" | base64 -w0)" \
  --query SequenceNumber --output text

echo "Published ${FILE_PATH} → s3://${INPUT_BUCKET}/${S3_KEY}"
echo "S3 notification put directly into Kinesis stream → Flink."  
