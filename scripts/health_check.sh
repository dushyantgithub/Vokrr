#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

APP_USERNAME="${APP_USERNAME:-admin}"
APP_PASSWORD="${APP_PASSWORD:-admin}"
BACKEND_URL="${BACKEND_URL:-http://localhost:8080}"
FRONTEND_URL="${FRONTEND_URL:-http://localhost:3000}"
HA_URL="${HOME_ASSISTANT_URL:-http://localhost:8123}"

check_http() {
  local name="$1"
  local url="$2"
  local expected="${3:-200}"
  local code
  code="$(curl -sS -o /tmp/quantum-home-health.out -w '%{http_code}' --max-time 10 "${url}" || true)"
  if [[ "${code}" != "${expected}" ]]; then
    echo "[FAIL] ${name}: expected HTTP ${expected}, got ${code}"
    cat /tmp/quantum-home-health.out 2>/dev/null || true
    exit 1
  fi
  echo "[ OK ] ${name}: HTTP ${code}"
}

echo "== Quantum Home health check =="

docker compose ps

check_http "frontend" "${FRONTEND_URL}" 200
check_http "backend health" "${BACKEND_URL}/api/system/health" 200
check_http "home assistant API unauthenticated probe" "${HA_URL}/api/" 401

TOKEN="$(
  curl -sS --max-time 10 \
    -H 'Content-Type: application/json' \
    -d "{\"username\":\"${APP_USERNAME}\",\"password\":\"${APP_PASSWORD}\"}" \
    "${BACKEND_URL}/api/auth/login" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])'
)"

ROOM_COUNT="$(
  curl -sS --max-time 10 \
    -H "Authorization: Bearer ${TOKEN}" \
    "${BACKEND_URL}/api/rooms" \
    | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))'
)"

SCENE_COUNT="$(
  curl -sS --max-time 10 \
    -H "Authorization: Bearer ${TOKEN}" \
    "${BACKEND_URL}/api/scenes" \
    | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))'
)"

echo "[ OK ] authenticated rooms: ${ROOM_COUNT}"
echo "[ OK ] authenticated scenes: ${SCENE_COUNT}"
echo "Health check passed."

