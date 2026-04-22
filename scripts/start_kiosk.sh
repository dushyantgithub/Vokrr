#!/usr/bin/env bash
set -euo pipefail

APP_URL="${VOKRR_KIOSK_URL:-http://localhost:3000}"
PROFILE_DIR="${VOKRR_KIOSK_PROFILE:-$HOME/.config/vokrr-kiosk}"
HEALTH_URL="${VOKRR_KIOSK_HEALTH_URL:-http://localhost:8080/api/system/health}"
STARTUP_TIMEOUT="${VOKRR_KIOSK_STARTUP_TIMEOUT:-180}"

mkdir -p "${PROFILE_DIR}"

pkill -u "$USER" -f "chromium.*vokrr-kiosk" 2>/dev/null || true
pkill -u "$USER" -f "chromium.*${APP_URL}" 2>/dev/null || true

# Wait for the backend (and, transitively, Home Assistant) to be healthy before
# launching Chromium. Without this gate the UI loads while the containers are
# still booting, the initial fetches fail, and the user sees a stale
# "Backend unavailable" notification with no devices until a manual refresh.
deadline=$(( $(date +%s) + STARTUP_TIMEOUT ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  payload=$(curl -fsS --max-time 2 "${HEALTH_URL}" 2>/dev/null || true)
  if [ -n "${payload}" ] && printf '%s' "${payload}" | grep -q '"home_assistant":[[:space:]]*{[[:space:]]*"ok":[[:space:]]*true'; then
    break
  fi
  sleep 2
done

exec /usr/bin/chromium-browser \
  --user-data-dir="${PROFILE_DIR}" \
  --ozone-platform=wayland \
  --app="${APP_URL}" \
  --kiosk \
  --start-fullscreen \
  --no-first-run \
  --no-default-browser-check \
  --disable-infobars \
  --disable-session-crashed-bubble \
  --disable-features=TranslateUI \
  --overscroll-history-navigation=0 \
  --password-store=basic
