#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.localaws.yml"
COMPOSE_ENV_FILE="${ROOT_DIR}/.env.local"
COMPOSE_ARGS=( -f "${COMPOSE_FILE}" )

if [[ -f "${COMPOSE_ENV_FILE}" ]]; then
  COMPOSE_ARGS=( --env-file "${COMPOSE_ENV_FILE}" "${COMPOSE_ARGS[@]}" )
fi

cd "${ROOT_DIR}"

"${ROOT_DIR}/scripts/local-preflight.sh"

mvn -q -DskipTests clean package

# Wipe any stale local state so postgres, Trino JDBC catalog, and the warehouse
# always start from a known-clean baseline.  postgres-data is owned by the
# Postgres container user (uid 999), so Docker-assisted removal is required.
echo "Cleaning local state (postgres-data, warehouse, checkpoints, savepoints)..."
mkdir -p local-data/postgres-data local-data/warehouse local-data/checkpoints local-data/savepoints
docker run --rm \
  -v "${ROOT_DIR}/local-data:/data" \
  alpine:3.20 sh -c \
  'rm -rf /data/postgres-data/* /data/postgres-data/.[!.]*
          /data/warehouse/* /data/warehouse/.[!.]*
          /data/checkpoints/* /data/checkpoints/.[!.]*
          /data/savepoints/* /data/savepoints/.[!.]* 2>/dev/null; true
   chmod -R a+rwx /data'

if ! docker compose "${COMPOSE_ARGS[@]}" up -d; then
  echo "Compose startup failed. Recent MiniStack logs:"
  docker compose "${COMPOSE_ARGS[@]}" logs --no-color --tail=200 ministack || true
  exit 1
fi

echo "Waiting for MiniStack readiness..."
MINISTACK_READY=false
for _ in $(seq 1 60); do
  if curl -sf http://localhost:4566/_ministack/health >/dev/null 2>&1; then
    MINISTACK_READY=true
    break
  fi
  sleep 1
done

if [[ "${MINISTACK_READY}" != "true" ]]; then
  echo "MiniStack did not become ready in time. Recent logs:"
  docker compose "${COMPOSE_ARGS[@]}" logs --no-color --tail=200 ministack || true
  exit 1
fi

echo "Initialising MiniStack resources..."
MINISTACK_ENDPOINT=http://localhost:4566 \
  AWS_ACCESS_KEY_ID=test \
  AWS_SECRET_ACCESS_KEY=test \
  "${ROOT_DIR}/scripts/ministack-init.sh"

echo "Waiting for Trino readiness..."
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

echo "Creating Iceberg schema and table (if not exists)..."
TABLE_CREATED=false
for _ in $(seq 1 10); do
  if docker compose "${COMPOSE_ARGS[@]}" exec -T trino \
    trino --user "${TRINO_USER:-datapike}" --execute \
    "CREATE SCHEMA IF NOT EXISTS iceberg.weather_db
         WITH (location = 'file:///opt/flink/local-warehouse/weather_db');
     CREATE TABLE IF NOT EXISTS iceberg.weather_db.temperature_summary (
         yyyy_mm_dd  VARCHAR,
         city_temps  MAP(VARCHAR, DOUBLE)
     ) WITH (
         format         = 'AVRO',
         format_version = 2
     )" 2>/dev/null; then
    TABLE_CREATED=true
    break
  fi
  echo "  Waiting for Trino JDBC catalog to initialise..."
  sleep 3
done

if [[ "${TABLE_CREATED}" != "true" ]]; then
  echo "ERROR: Failed to create Iceberg table via Trino after retries."
  docker compose "${COMPOSE_ARGS[@]}" logs --no-color --tail=50 trino || true
  exit 1
fi

# Trino's CREATE SCHEMA creates the warehouse subdirectory with restrictive
# permissions (owned by the Trino container user). Grant write access so the
# Flink taskmanager container can create data files there.
docker run --rm \
  -v "${ROOT_DIR}/local-data:/data" \
  alpine:3.20 chmod -R a+rwx /data

docker compose "${COMPOSE_ARGS[@]}" exec -T jobmanager \
  flink run "/opt/flink/usrlib/$(basename "${JAR_PATH}")"

echo "Local-AWS stack started and Flink job submitted."
echo "Flink UI:    http://localhost:8081"
echo "MiniStack:   http://localhost:4566"
echo "Trino UI:    http://localhost:8080"
