#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.local.yml"
COMPOSE_ENV_FILE="${ROOT_DIR}/.env.local"
COMPOSE_ARGS=( -f "${COMPOSE_FILE}" )
PURGE="${1:-}"

if [[ -f "${COMPOSE_ENV_FILE}" ]]; then
  COMPOSE_ARGS=( --env-file "${COMPOSE_ENV_FILE}" "${COMPOSE_ARGS[@]}" )
fi

cd "${ROOT_DIR}"

if [[ "${PURGE}" == "--purge" ]]; then
  docker compose "${COMPOSE_ARGS[@]}" down --remove-orphans --volumes
  if ! rm -rf local-data; then
    echo "Local host cleanup failed due to permissions. Trying Docker-assisted cleanup..."
    mkdir -p local-data
    docker run --rm -v "${ROOT_DIR}/local-data:/data" alpine:3.20 sh -c 'rm -rf /data/* /data/.[!.]* /data/..?*' || true
    rm -rf local-data
  fi
  echo "Local stack stopped and local-data removed."
  exit 0
fi

docker compose "${COMPOSE_ARGS[@]}" down --remove-orphans

echo "Local stack stopped."
echo "Use './scripts/local-down.sh --purge' to also remove local-data."
