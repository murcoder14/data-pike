#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.local.yml"
COMPOSE_ENV_FILE="${ROOT_DIR}/.env.local"
COMPOSE_ARGS=( -f "${COMPOSE_FILE}" )
RABBIT_API="http://localhost:15672/api"

if [[ -f "${COMPOSE_ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${COMPOSE_ENV_FILE}"
  set +a
  COMPOSE_ARGS=( --env-file "${COMPOSE_ENV_FILE}" "${COMPOSE_ARGS[@]}" )
fi

RABBITMQ_USERNAME="${RABBITMQ_USERNAME:-datapike}"
RABBITMQ_PASSWORD="${RABBITMQ_PASSWORD:-datapike}"
AUTH="${RABBITMQ_USERNAME}:${RABBITMQ_PASSWORD}"
STREAM_NAME="${RABBITMQ_STREAM_NAME:-weather-stream}"

cd "${ROOT_DIR}"

MARKER_FILE="$(mktemp)"
trap 'rm -f "${MARKER_FILE}"' EXIT

touch "${MARKER_FILE}"

RUN_SEED="$(date +%s%N)"
RUN_DATE="$(python3 - <<'PY'
from datetime import date, timedelta
import time
seed = time.time_ns()
# Keep dates valid and deterministic per run while changing every execution.
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

# Ensure stream queue exists.
curl -sS -u "${AUTH}" -H "content-type:application/json" \
  -X PUT "${RABBIT_API}/queues/%2F/${STREAM_NAME}" \
  -d '{"auto_delete":false,"durable":true,"arguments":{"x-queue-type":"stream"}}' >/dev/null

publish() {
  local payload="$1"
  curl -sS -u "${AUTH}" -H "content-type:application/json" \
    -X POST "${RABBIT_API}/exchanges/%2F/amq.default/publish" \
    -d "{\"properties\":{},\"routing_key\":\"${STREAM_NAME}\",\"payload\":$(printf '%s' "${payload}" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'),\"payload_encoding\":\"string\"}" >/dev/null
}

PAYLOAD="[
  {\"date\":\"${RUN_DATE}\",\"city\":\"${CITY_ONE}\",\"temperature\":${TEMP_ONE}},
  {\"date\":\"${RUN_DATE}\",\"city\":\"${CITY_TWO}\",\"temperature\":${TEMP_TWO}},
  {\"date\":\"${RUN_DATE}\",\"city\":\"${CITY_THREE}\",\"temperature\":${TEMP_THREE}}
]"
publish "${PAYLOAD}"

echo "Published sample messages to stream ${STREAM_NAME} for date ${RUN_DATE}."

for _ in $(seq 1 30); do
  if find local-data/warehouse -type f -name '*.avro' -newer "${MARKER_FILE}" | grep -q .; then
    echo "Smoke test passed: new Iceberg Avro files detected in local-data/warehouse."
    exit 0
  fi
  sleep 1

done

echo "Smoke test failed: no new Avro files found under local-data/warehouse after 30s."
echo "Check logs: docker compose ${COMPOSE_ARGS[*]} logs --tail=200 jobmanager taskmanager"
exit 1
