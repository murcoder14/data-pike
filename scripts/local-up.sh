#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.local.yml"
COMPOSE_ENV_FILE="${ROOT_DIR}/.env.local"
COMPOSE_ARGS=( -f "${COMPOSE_FILE}" )

if [[ -f "${COMPOSE_ENV_FILE}" ]]; then
  COMPOSE_ARGS=( --env-file "${COMPOSE_ENV_FILE}" "${COMPOSE_ARGS[@]}" )
fi

cd "${ROOT_DIR}"

"${ROOT_DIR}/scripts/local-preflight.sh"

mvn -q -DskipTests clean package

mkdir -p local-data/warehouse local-data/checkpoints local-data/savepoints local-data/postgres-data

# Flink containers do not run as the host user; make bind-mounted dirs writable.
# In some environments local-data may be root-owned from prior cleanup runs.
if ! chmod -R a+rwx local-data; then
  echo "WARN: could not chmod local-data recursively; continuing with existing permissions."
fi

if ! docker compose "${COMPOSE_ARGS[@]}" up -d; then
  echo "Compose startup failed. Recent RabbitMQ logs:"
  docker compose "${COMPOSE_ARGS[@]}" logs --no-color --tail=200 rabbitmq || true
  exit 1
fi

echo "Waiting for Trino readiness..."
if ! docker compose "${COMPOSE_ARGS[@]}" config --services | grep -qx "trino"; then
  echo "Trino service is not defined in docker-compose.local.yml"
  exit 1
fi

TRINO_READY=false
for _ in $(seq 1 90); do
  if docker compose "${COMPOSE_ARGS[@]}" ps --status running --services | grep -qx "trino"; then
    if docker compose "${COMPOSE_ARGS[@]}" exec -T trino \
      trino --user "${TRINO_USER:-datapike}" --execute "SELECT 1" >/dev/null 2>&1; then
      TRINO_READY=true
      break
    fi
  fi
  sleep 2
done

if [[ "${TRINO_READY}" != "true" ]]; then
  echo "Trino did not become query-ready in time. Recent Trino logs:"
  docker compose "${COMPOSE_ARGS[@]}" logs --no-color --tail=200 trino || true
  exit 1
fi

JAR_PATH="$(ls target/data-pike-*.jar | grep -v original | head -n 1)"
if [[ -z "${JAR_PATH}" ]]; then
  echo "Could not find built jar under target/."
  exit 1
fi

docker compose "${COMPOSE_ARGS[@]}" exec -T jobmanager \
  flink run "/opt/flink/usrlib/$(basename "${JAR_PATH}")"

echo "Local stack started and Flink job submitted."
echo "Flink UI: http://localhost:8081"
echo "RabbitMQ UI: http://localhost:15672"
echo "Trino UI: http://localhost:8080"
