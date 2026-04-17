#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.local.yml"
COMPOSE_ENV_FILE="${ROOT_DIR}/.env.local"
COMPOSE_ARGS=( -f "${COMPOSE_FILE}" )
SQL="${1:-SELECT * FROM iceberg.default.temperature_summary ORDER BY date LIMIT 20}"
TRINO_USER="${TRINO_USER:-datapike}"
TRINO_CATALOG="${TRINO_CATALOG:-iceberg}"
TRINO_SCHEMA="${TRINO_SCHEMA:-default}"

if [[ -f "${COMPOSE_ENV_FILE}" ]]; then
  COMPOSE_ARGS=( --env-file "${COMPOSE_ENV_FILE}" "${COMPOSE_ARGS[@]}" )
fi

cd "${ROOT_DIR}"

ensure_docker_access() {
  local err
  if ! err="$(docker info 2>&1 >/dev/null)"; then
    echo "Docker is not accessible:"
    echo "${err}"
    echo "If Docker is running, verify your user can access /var/run/docker.sock."
    exit 1
  fi
}

ensure_trino_running() {
  local services
  local err

  if ! services="$(docker compose "${COMPOSE_ARGS[@]}" config --services 2>/dev/null)"; then
    err="$(docker compose "${COMPOSE_ARGS[@]}" config --services 2>&1 || true)"
    echo "Unable to read compose services:"
    echo "${err}"
    exit 1
  fi

  if ! grep -qx "trino" <<<"${services}"; then
    echo "Trino service is not defined in docker-compose.local.yml"
    exit 1
  fi

  if ! services="$(docker compose "${COMPOSE_ARGS[@]}" ps --status running --services 2>/dev/null)"; then
    err="$(docker compose "${COMPOSE_ARGS[@]}" ps --status running --services 2>&1 || true)"
    echo "Unable to inspect compose services:"
    echo "${err}"
    exit 1
  fi

  if ! grep -qx "trino" <<<"${services}"; then
    echo "Trino service is not running. Start services first with:"
    echo "  ./scripts/local-up.sh"
    exit 1
  fi
}

ensure_docker_access
ensure_trino_running

docker compose "${COMPOSE_ARGS[@]}" exec -T trino \
  trino --user "${TRINO_USER}" --catalog "${TRINO_CATALOG}" --schema "${TRINO_SCHEMA}" \
    --output-format CSV_HEADER --execute "${SQL}"
