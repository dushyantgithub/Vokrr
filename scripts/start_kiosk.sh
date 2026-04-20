#!/usr/bin/env bash
set -euo pipefail

APP_URL="${QUANTUM_HOME_KIOSK_URL:-http://localhost:3000}"
PROFILE_DIR="${QUANTUM_HOME_KIOSK_PROFILE:-$HOME/.config/quantum-home-kiosk}"

mkdir -p "${PROFILE_DIR}"

pkill -u "$USER" -f "chromium.*quantum-home-kiosk" 2>/dev/null || true
pkill -u "$USER" -f "chromium.*${APP_URL}" 2>/dev/null || true

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
