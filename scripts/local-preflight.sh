#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKIP_PORT_CHECK="${SKIP_PORT_CHECK:-false}"

fail() {
  echo "[preflight] ERROR: $1" >&2
  exit 1
}

check_command() {
  local name="$1"
  command -v "${name}" >/dev/null 2>&1 || fail "Missing required command '${name}'."
}

check_port_free() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    if ss -ltn "sport = :${port}" | tail -n +2 | grep -q .; then
      fail "Port ${port} is already in use. Stop the conflicting service or set SKIP_PORT_CHECK=true."
    fi
    return
  fi

  if command -v netstat >/dev/null 2>&1; then
    if netstat -ltn 2>/dev/null | awk '{print $4}' | grep -E "(^|:)${port}$" -q; then
      fail "Port ${port} is already in use. Stop the conflicting service or set SKIP_PORT_CHECK=true."
    fi
    return
  fi

  echo "[preflight] WARN: Neither 'ss' nor 'netstat' found; skipping port checks."
}

echo "[preflight] Checking local dependencies..."
check_command java
check_command mvn
check_command docker
check_command curl
check_command python3

echo "[preflight] Checking Docker daemon..."
if ! DOCKER_ERR="$(docker info 2>&1 >/dev/null)"; then
  fail "Docker daemon is not reachable. ${DOCKER_ERR} If Docker is running, ensure your user can access /var/run/docker.sock."
fi

if [[ "${SKIP_PORT_CHECK}" != "true" ]]; then
  echo "[preflight] Checking required local ports..."
  check_port_free 8081
  check_port_free 8080
  check_port_free 15672
  check_port_free 5552
  check_port_free 5433
else
  echo "[preflight] SKIP_PORT_CHECK=true; skipping port checks."
fi

if [[ ! -f "${ROOT_DIR}/docker-compose.local.yml" ]]; then
  fail "Missing docker-compose.local.yml in ${ROOT_DIR}."
fi

echo "[preflight] OK: local environment is ready."
