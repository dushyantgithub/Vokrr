#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${VOKRR_APP_DIR:-/home/dushyant/apps/Vokrr}"
ENV_FILES=("${APP_DIR}/.env" "${APP_DIR}/scripts/.env")
WIFI_IFACE="${VOKRR_WIFI_IFACE:-wlan0}"

read_env_value() {
  local key="$1"
  local value=""
  local file line

  for file in "${ENV_FILES[@]}"; do
    [[ -f "${file}" ]] || continue
    line="$(grep -E "^${key}=" "${file}" | tail -n 1 || true)"
    [[ -n "${line}" ]] || continue
    value="${line#*=}"
  done

  printf '%s' "${value}"
}

connection_exists() {
  local name="$1"
  nmcli -t -f NAME connection show | grep -Fxq "${name}"
}

configure_connection() {
  local name="$1"
  local ssid="$2"
  local password="$3"
  local priority="$4"

  [[ -n "${ssid}" ]] || return 0

  if connection_exists "${name}"; then
    nmcli connection modify "${name}" \
      connection.autoconnect yes \
      connection.autoconnect-priority "${priority}" \
      802-11-wireless.ssid "${ssid}" \
      802-11-wireless.mode infrastructure \
      ipv4.method auto \
      ipv6.method auto >/dev/null
  else
    nmcli connection add type wifi ifname "*" con-name "${name}" ssid "${ssid}" \
      connection.autoconnect yes \
      connection.autoconnect-priority "${priority}" \
      802-11-wireless.mode infrastructure \
      ipv4.method auto \
      ipv6.method auto >/dev/null
  fi

  if [[ -n "${password}" ]]; then
    nmcli connection modify "${name}" \
      802-11-wireless-security.key-mgmt wpa-psk \
      802-11-wireless-security.psk "${password}" >/dev/null
  fi
}

network_visible() {
  local ssid="$1"
  nmcli -t -f SSID device wifi list ifname "${WIFI_IFACE}" | grep -Fxq "${ssid}"
}

connect_if_visible() {
  local name="$1"
  local ssid="$2"

  [[ -n "${ssid}" ]] || return 1
  if network_visible "${ssid}"; then
    nmcli connection up "${name}" ifname "${WIFI_IFACE}" >/dev/null
    return 0
  fi

  return 1
}

main() {
  if ! command -v nmcli >/dev/null 2>&1; then
    echo "NetworkManager CLI (nmcli) is required." >&2
    exit 1
  fi

  local primary_ssid primary_password secondary_ssid secondary_password current_ssid
  primary_ssid="$(read_env_value PRIMARY_SSID)"
  primary_password="$(read_env_value PRIMARY_SSID_PASSWORD)"
  secondary_ssid="$(read_env_value SECONDARY_SSID)"
  secondary_password="$(read_env_value SECONDARY_SSID_PASSWORD)"

  if [[ -z "${primary_ssid}" && -z "${secondary_ssid}" ]]; then
    echo "No PRIMARY_SSID or SECONDARY_SSID configured in .env files." >&2
    exit 1
  fi

  nmcli radio wifi on >/dev/null

  configure_connection "vokrr-primary-wifi" "${primary_ssid}" "${primary_password}" 20
  configure_connection "vokrr-secondary-wifi" "${secondary_ssid}" "${secondary_password}" 10

  nmcli device wifi rescan ifname "${WIFI_IFACE}" >/dev/null 2>&1 || true
  sleep 2

  current_ssid="$(nmcli -t -f ACTIVE,SSID device wifi list ifname "${WIFI_IFACE}" | awk -F: '$1 == "yes" { print $2; exit }')"
  if [[ "${current_ssid}" == "${primary_ssid}" || "${current_ssid}" == "${secondary_ssid}" ]]; then
    echo "Wi-Fi already connected to a configured Vokrr network."
    exit 0
  fi

  connect_if_visible "vokrr-primary-wifi" "${primary_ssid}" && {
    echo "Connected to primary Vokrr Wi-Fi network."
    exit 0
  }

  connect_if_visible "vokrr-secondary-wifi" "${secondary_ssid}" && {
    echo "Connected to secondary Vokrr Wi-Fi network."
    exit 0
  }

  echo "Configured Vokrr Wi-Fi networks; neither SSID is currently visible."
}

main "$@"
