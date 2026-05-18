#!/usr/bin/env bash
set -euo pipefail

APP_BIN="${VOKRR_QT_BIN:-/home/dushyant/apps/Vokrr/qt-frontend/build/vokrr-qt}"
API_BASE="${VOKRR_API_BASE:-http://localhost:8080}"
STARTUP_TIMEOUT="${VOKRR_KIOSK_STARTUP_TIMEOUT:-180}"
DISPLAY_TIMEOUT="${VOKRR_KIOSK_DISPLAY_TIMEOUT:-60}"

if [ ! -x "${APP_BIN}" ]; then
  echo "Vokrr Qt app binary not found or not executable: ${APP_BIN}" >&2
  exit 1
fi

pkill -u "$USER" -x "vokrr-qt" 2>/dev/null || true

display_deadline=$(( $(date +%s) + DISPLAY_TIMEOUT ))
while [ "$(date +%s)" -lt "$display_deadline" ]; do
  runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  if [ -n "${WAYLAND_DISPLAY:-}" ] && [ -S "${runtime_dir}/${WAYLAND_DISPLAY}" ]; then
    export XDG_RUNTIME_DIR="${runtime_dir}"
    export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-wayland}"
    break
  fi
  if [ -n "${DISPLAY:-}" ]; then
    display_num="${DISPLAY#:}"
    display_num="${display_num%%.*}"
    if [ -S "/tmp/.X11-unix/X${display_num}" ]; then
      export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-xcb}"
      break
    fi
  fi
  if [ -S /tmp/.X11-unix/X0 ]; then
    export DISPLAY=:0
    export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-xcb}"
    break
  fi
  sleep 1
done

if [ -z "${QT_QPA_PLATFORM:-}" ]; then
  echo "No Wayland or X11 display session found for Vokrr Qt launch." >&2
  exit 1
fi

if command -v xset >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
  xset s off -dpms s noblank 2>/dev/null || true
fi

if command -v xinput >/dev/null 2>&1 && command -v xrandr >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
  touch_id="$(
    xinput list --id-only '10-0038 generic ft5x06 (79)' 2>/dev/null ||
    xinput list --id-only 'raspberrypi-ts' 2>/dev/null ||
    xinput list --id-only 'Raspberry Pi Touchscreen' 2>/dev/null ||
    xinput list --id-only 'FT5406 memory based driver' 2>/dev/null ||
    true
  )"
  touch_output="$(
    xrandr --query 2>/dev/null | awk '
      $2 == "connected" && $1 ~ /^DSI-/ { print $1; exit }
      $2 == "connected" && $0 ~ /800x480/ { candidate = $1 }
      END { if (candidate) print candidate }
    '
  )"
  if [ -z "${touch_output}" ]; then
    touch_output="$(xrandr --query 2>/dev/null | awk '$2 == "connected" && $3 ~ /^\+/ { print $1; exit }')"
  fi
  if [ -z "${touch_output}" ]; then
    touch_output="$(xrandr --query 2>/dev/null | awk '$2 == "connected" { print $1; exit }')"
  fi
  if [ -n "${touch_id}" ] && [ -n "${touch_output}" ]; then
    xinput map-to-output "${touch_id}" "${touch_output}" 2>/dev/null || true
    touch_rotation="${VOKRR_TOUCH_ROTATION:-}"
    if [ -z "${touch_rotation}" ] && [ -r /proc/cmdline ]; then
      touch_rotation="$(tr ' ' '\n' < /proc/cmdline | awk -F'rotate=' '/^video=DSI-[0-9]:/ && NF > 1 { split($2, parts, /[, ]/); print parts[1]; exit }')"
    fi
    if [ "${touch_rotation}" = "180" ]; then
      xinput set-prop "${touch_id}" 'Coordinate Transformation Matrix' -1 0 1 0 -1 1 0 0 1 2>/dev/null || true
    fi
  fi
fi

deadline=$(( $(date +%s) + STARTUP_TIMEOUT ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  payload="$(curl -fsS --max-time 2 "${API_BASE}/api/system/health" 2>/dev/null || true)"
  if [ -n "${payload}" ] && printf '%s' "${payload}" | grep -q '"ok":[[:space:]]*true'; then
    break
  fi
  sleep 2
done

export VOKRR_API_BASE="${API_BASE}"
export QT_XCB_NO_XI2="${QT_XCB_NO_XI2:-0}"
exec "${APP_BIN}"
