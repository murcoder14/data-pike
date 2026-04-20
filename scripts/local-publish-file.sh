#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_ENV_FILE="${ROOT_DIR}/.env.local"
RABBIT_API="http://localhost:15672/api"

if [[ -f "${COMPOSE_ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${COMPOSE_ENV_FILE}"
  set +a
fi

RABBITMQ_USERNAME="${RABBITMQ_USERNAME:-datapike}"
RABBITMQ_PASSWORD="${RABBITMQ_PASSWORD:-datapike}"
STREAM_NAME="${RABBITMQ_STREAM_NAME:-weather-stream}"
AUTH="${RABBITMQ_USERNAME}:${RABBITMQ_PASSWORD}"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/local-publish-file.sh json
  ./scripts/local-publish-file.sh xml
  ./scripts/local-publish-file.sh csv
  ./scripts/local-publish-file.sh tsv
  ./scripts/local-publish-file.sh <path-to-file>

Examples:
  ./scripts/local-publish-file.sh src/test/resources/weather_data.json
  ./scripts/local-publish-file.sh src/test/resources/weather_data.xml
  ./scripts/local-publish-file.sh src/test/resources/weather_data.csv
  ./scripts/local-publish-file.sh src/test/resources/weather_data.tsv
EOF
}

resolve_input_file() {
  local input="$1"
  case "${input}" in
    json)
      echo "${ROOT_DIR}/src/test/resources/weather_data.json"
      ;;
    xml)
      echo "${ROOT_DIR}/src/test/resources/weather_data.xml"
      ;;
    csv)
      echo "${ROOT_DIR}/src/test/resources/weather_data.csv"
      ;;
    tsv)
      echo "${ROOT_DIR}/src/test/resources/weather_data.tsv"
      ;;
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

INPUT="$1"
FILE_PATH="$(resolve_input_file "${INPUT}")"

if [[ ! -f "${FILE_PATH}" ]]; then
  echo "File not found: ${FILE_PATH}"
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "Missing required command: curl"
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "Missing required command: python3"
  exit 1
fi

# Ensure stream queue exists.
curl -sS -u "${AUTH}" -H "content-type:application/json" \
  -X PUT "${RABBIT_API}/queues/%2F/${STREAM_NAME}" \
  -d '{"auto_delete":false,"durable":true,"arguments":{"x-queue-type":"stream"}}' >/dev/null

PAYLOAD_JSON="$(python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' < "${FILE_PATH}")"

curl -sS -u "${AUTH}" -H "content-type:application/json" \
  -X POST "${RABBIT_API}/exchanges/%2F/amq.default/publish" \
  -d "{\"properties\":{},\"routing_key\":\"${STREAM_NAME}\",\"payload\":${PAYLOAD_JSON},\"payload_encoding\":\"string\"}" >/dev/null

echo "Published ${FILE_PATH} to stream ${STREAM_NAME}."
