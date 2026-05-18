#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

load_env_file() {
  local file="$1" key value
  while IFS='=' read -r key value || [[ -n "${key}" ]]; do
    [[ -z "${key}" || "${key}" == \#* ]] && continue
    [[ "${key}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    export "${key}=${value}"
  done < "${file}"
}

if [[ -f scripts/.env ]]; then
  load_env_file scripts/.env
elif [[ -f .env ]]; then
  load_env_file .env
fi

APP_USERNAME="${APP_BOOTSTRAP_ADMIN_USERNAME:-${APP_USERNAME:-admin}}"
APP_PASSWORD="${APP_BOOTSTRAP_ADMIN_PASSWORD:-${APP_PASSWORD:-admin}}"
BACKEND_URL="${BACKEND_URL:-http://localhost:8080}"
HA_URL="${HOME_ASSISTANT_URL:-http://localhost:8123}"

check_http() {
  local name="$1"
  local url="$2"
  local expected="${3:-200}"
  local code
  for _ in {1..20}; do
    code="$(curl -sS -o /tmp/vokrr-health.out -w '%{http_code}' --max-time 10 "${url}" || true)"
    if [[ "${code}" == "${expected}" ]]; then
      echo "[ OK ] ${name}: HTTP ${code}"
      return
    fi
    sleep 3
  done
  if [[ "${code}" != "${expected}" ]]; then
    echo "[FAIL] ${name}: expected HTTP ${expected}, got ${code}"
    cat /tmp/vokrr-health.out 2>/dev/null || true
    exit 1
  fi
}

echo "== Vokrr health check =="

docker compose ps

if scripts/select_audio_output.sh >/tmp/vokrr-audio-select.out 2>&1; then
  cat /tmp/vokrr-audio-select.out
  if [[ -f backend/data/audio-output.env ]]; then
    grep -E '^(VOKRR_AUDIO_DEVICE|VOKRR_AUDIO_OUTPUT_KIND)=' backend/data/audio-output.env || true
  fi
else
  echo "[FAIL] audio output detection failed"
  cat /tmp/vokrr-audio-select.out 2>/dev/null || true
  exit 1
fi

check_http "backend health" "${BACKEND_URL}/api/system/health" 200
check_http "home assistant API unauthenticated probe" "${HA_URL}/api/" 401
if systemctl is-active --quiet vokrr-kiosk.service; then
  echo "[ OK ] native Qt kiosk: systemd active"
else
  echo "[FAIL] native Qt kiosk: systemd inactive"
  systemctl --no-pager --full status vokrr-kiosk.service || true
  exit 1
fi

TOKEN="$(
  curl -sS --max-time 10 \
    -H 'Content-Type: application/json' \
    -d "{\"username\":\"${APP_USERNAME}\",\"password\":\"${APP_PASSWORD}\"}" \
    "${BACKEND_URL}/api/auth/login" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])'
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
