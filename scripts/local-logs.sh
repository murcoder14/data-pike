#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.local.yml"
COMPOSE_ENV_FILE="${ROOT_DIR}/.env.local"
COMPOSE_ARGS=( -f "${COMPOSE_FILE}" )
OUT_DIR="${ROOT_DIR}/local-data/logs"
STAMP="$(date +%Y%m%d-%H%M%S)"
DEST="${OUT_DIR}/${STAMP}"

if [[ -f "${COMPOSE_ENV_FILE}" ]]; then
	COMPOSE_ARGS=( --env-file "${COMPOSE_ENV_FILE}" "${COMPOSE_ARGS[@]}" )
fi

mkdir -p "${DEST}"

cd "${ROOT_DIR}"

docker compose "${COMPOSE_ARGS[@]}" logs --no-color rabbitmq > "${DEST}/rabbitmq.log" || true
docker compose "${COMPOSE_ARGS[@]}" logs --no-color jobmanager > "${DEST}/jobmanager.log" || true
docker compose "${COMPOSE_ARGS[@]}" logs --no-color taskmanager > "${DEST}/taskmanager.log" || true
docker compose "${COMPOSE_ARGS[@]}" logs --no-color trino > "${DEST}/trino.log" || true

echo "Logs written to ${DEST}" 
