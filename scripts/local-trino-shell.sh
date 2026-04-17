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

  if ! services="$(docker compose "${COMPOSE_ARGS[@]}" ps --status running --services 2>/dev/null)"; then
    err="$(docker compose "${COMPOSE_ARGS[@]}" ps --status running --services 2>&1 || true)"
    echo "Unable to inspect compose services:"
    echo "${err}"
    exit 1
  fi

  if grep -qx "trino" <<<"${services}"; then
    return 0
  fi

  echo "Trino service is not running. Start the local stack first:"
  echo "  ./scripts/local-up.sh"
  exit 1
}

ensure_docker_access
ensure_trino_running

TRINO_USER="${TRINO_USER:-datapike}"
TRINO_CATALOG="${TRINO_CATALOG:-iceberg}"
TRINO_SCHEMA="${TRINO_SCHEMA:-default}"

docker compose "${COMPOSE_ARGS[@]}" exec trino \
  trino --user "${TRINO_USER}" --catalog "${TRINO_CATALOG}" --schema "${TRINO_SCHEMA}"
