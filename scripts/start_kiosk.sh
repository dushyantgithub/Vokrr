#!/usr/bin/env bash
set -euo pipefail

APP_URL="${VOKRR_KIOSK_URL:-http://localhost:3000}"
PROFILE_DIR="${VOKRR_KIOSK_PROFILE:-$HOME/.config/vokrr-kiosk}"
HEALTH_URL="${VOKRR_KIOSK_HEALTH_URL:-http://localhost:8080/api/system/health}"
STARTUP_TIMEOUT="${VOKRR_KIOSK_STARTUP_TIMEOUT:-180}"
DISPLAY_TIMEOUT="${VOKRR_KIOSK_DISPLAY_TIMEOUT:-60}"

mkdir -p "${PROFILE_DIR}"

pkill -u "$USER" -f "chromium.*vokrr-kiosk" 2>/dev/null || true
pkill -u "$USER" -f "chromium.*${APP_URL}" 2>/dev/null || true

chromium_bin="$(command -v chromium-browser 2>/dev/null || true)"
if [ -z "${chromium_bin}" ]; then
  chromium_bin="$(command -v chromium 2>/dev/null || true)"
fi
if [ -z "${chromium_bin}" ]; then
  echo "Chromium is not installed. Install chromium-browser or chromium." >&2
  exit 1
fi

browser_flags=()
display_deadline=$(( $(date +%s) + DISPLAY_TIMEOUT ))
while [ "$(date +%s)" -lt "$display_deadline" ]; do
  runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  if [ -n "${WAYLAND_DISPLAY:-}" ] && [ -S "${runtime_dir}/${WAYLAND_DISPLAY}" ]; then
    export XDG_RUNTIME_DIR="${runtime_dir}"
    browser_flags+=(--ozone-platform=wayland)
    break
  fi
  if [ -n "${DISPLAY:-}" ]; then
    display_num="${DISPLAY#:}"
    display_num="${display_num%%.*}"
    if [ -S "/tmp/.X11-unix/X${display_num}" ]; then
      browser_flags+=(--ozone-platform=x11)
      break
    fi
  fi
  if [ -S /tmp/.X11-unix/X0 ]; then
    export DISPLAY=:0
    browser_flags+=(--ozone-platform=x11)
    break
  fi
  sleep 1
done

if [ "${#browser_flags[@]}" -eq 0 ]; then
  echo "No Wayland or X11 display session found for kiosk launch." >&2
  exit 1
fi

if command -v xset >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
  xset s off -dpms s noblank 2>/dev/null || true
fi

# Wait for the web UI and backend process to answer before launching Chromium.
# Home Assistant may still be starting; the app can load and show its own health
# state as long as the frontend and backend containers are reachable.
deadline=$(( $(date +%s) + STARTUP_TIMEOUT ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  frontend_ok=0
  backend_ok=0
  curl -fsS --max-time 2 "${APP_URL}" >/dev/null 2>&1 && frontend_ok=1
  payload="$(curl -fsS --max-time 2 "${HEALTH_URL}" 2>/dev/null || true)"
  if [ -n "${payload}" ] && printf '%s' "${payload}" | grep -q '"ok":[[:space:]]*true'; then
    backend_ok=1
  fi
  if [ "${frontend_ok}" -eq 1 ] && [ "${backend_ok}" -eq 1 ]; then
    break
  fi
  sleep 2
done

exec "${chromium_bin}" \
  --user-data-dir="${PROFILE_DIR}" \
  "${browser_flags[@]}" \
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
