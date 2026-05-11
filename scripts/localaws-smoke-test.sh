#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.localaws.yml"
COMPOSE_ENV_FILE="${ROOT_DIR}/.env.local"
COMPOSE_ARGS=( -f "${COMPOSE_FILE}" )

if [[ -f "${COMPOSE_ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${COMPOSE_ENV_FILE}"
  set +a
  COMPOSE_ARGS=( --env-file "${COMPOSE_ENV_FILE}" "${COMPOSE_ARGS[@]}" )
fi

ENDPOINT="${MINISTACK_ENDPOINT:-http://localhost:4566}"
INPUT_BUCKET="${INPUT_BUCKET:-data-pike-input}"
REGION="${AWS_REGION:-us-east-1}"
AWS="aws --endpoint-url ${ENDPOINT} --region ${REGION}"

cd "${ROOT_DIR}"

MARKER_FILE="$(mktemp)"
trap 'rm -f "${MARKER_FILE}"' EXIT
touch "${MARKER_FILE}"

RUN_SEED="$(date +%s%N)"
RUN_DATE="$(python3 - <<'PY'
from datetime import date, timedelta
import time
seed = time.time_ns()
run_date = date(2026, 1, 1) + timedelta(days=seed % 365)
print(run_date.isoformat())
PY
)"

CITY_SUFFIX="${RUN_SEED: -4}"
TEMP_BASE="$(( (RUN_SEED % 10) + 20 ))"
CITY_ONE="Bengaluru-${CITY_SUFFIX}"
CITY_TWO="Chennai-${CITY_SUFFIX}"
CITY_THREE="Pune-${CITY_SUFFIX}"
TEMP_ONE="${TEMP_BASE}"
TEMP_TWO="$((TEMP_BASE + 5))"
TEMP_THREE="$((TEMP_BASE - 3))"

PAYLOAD="[
  {\"date\":\"${RUN_DATE}\",\"city\":\"${CITY_ONE}\",\"temperature\":${TEMP_ONE}},
  {\"date\":\"${RUN_DATE}\",\"city\":\"${CITY_TWO}\",\"temperature\":${TEMP_TWO}},
  {\"date\":\"${RUN_DATE}\",\"city\":\"${CITY_THREE}\",\"temperature\":${TEMP_THREE}}
]"

TMPFILE="$(mktemp --suffix=.json)"
trap 'rm -f "${TMPFILE}" "${MARKER_FILE}"' EXIT
printf '%s' "${PAYLOAD}" > "${TMPFILE}"

S3_KEY="data/smoke-test-${RUN_SEED}.json"
AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test \
  ${AWS} s3 cp "${TMPFILE}" "s3://${INPUT_BUCKET}/${S3_KEY}"

echo "Published smoke payload → s3://${INPUT_BUCKET}/${S3_KEY} for date ${RUN_DATE}."

for _ in $(seq 1 30); do
  if find local-data/warehouse -type f -name '*.avro' -newer "${MARKER_FILE}" | grep -q .; then
    echo "Smoke test passed: new Iceberg Avro files detected in local-data/warehouse."
    exit 0
  fi
  sleep 1
done

echo "Smoke test failed: no new Avro files found under local-data/warehouse after 30s."
exit 1
