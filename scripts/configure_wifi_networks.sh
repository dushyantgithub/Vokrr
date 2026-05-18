#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${VOKRR_APP_DIR:-/home/dushyant/apps/Vokrr}"
ENV_FILES=("${APP_DIR}/.env" "${APP_DIR}/scripts/.env")
WIFI_IFACE="${VOKRR_WIFI_IFACE:-wlan0}"
SCAN_TIMEOUT_SECONDS="${VOKRR_WIFI_SCAN_TIMEOUT_SECONDS:-60}"
SCAN_INTERVAL_SECONDS="${VOKRR_WIFI_SCAN_INTERVAL_SECONDS:-5}"

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
      connection.interface-name "${WIFI_IFACE}" \
      802-11-wireless.ssid "${ssid}" \
      802-11-wireless.mode infrastructure \
      ipv4.method auto \
      ipv6.method auto >/dev/null
  else
    nmcli connection add type wifi ifname "*" con-name "${name}" ssid "${ssid}" \
      connection.autoconnect yes \
      connection.autoconnect-priority "${priority}" \
      connection.interface-name "${WIFI_IFACE}" \
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

active_ssid() {
  nmcli -t -f ACTIVE,SSID device wifi list ifname "${WIFI_IFACE}" | awk -F: '$1 == "yes" { print $2; exit }'
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

connect_available_network() {
  local primary_ssid="$1"
  local secondary_ssid="$2"

  connect_if_visible "vokrr-primary-wifi" "${primary_ssid}" && {
    echo "Connected to primary Vokrr Wi-Fi network."
    return 0
  }

  connect_if_visible "vokrr-secondary-wifi" "${secondary_ssid}" && {
    echo "Connected to secondary Vokrr Wi-Fi network."
    return 0
  }

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

  local deadline
  deadline=$(( $(date +%s) + SCAN_TIMEOUT_SECONDS ))
  while [[ "$(date +%s)" -lt "${deadline}" ]]; do
    nmcli device set "${WIFI_IFACE}" managed yes >/dev/null 2>&1 || true
    nmcli device wifi rescan ifname "${WIFI_IFACE}" >/dev/null 2>&1 || true
    sleep 2

    current_ssid="$(active_ssid)"
    if [[ -n "${primary_ssid}" && "${current_ssid}" == "${primary_ssid}" ]]; then
      echo "Wi-Fi already connected to primary Vokrr Wi-Fi network."
      exit 0
    fi

    # Primary must always win when visible, even if NetworkManager connected to
    # secondary first during boot.
    connect_available_network "${primary_ssid}" "${secondary_ssid}" && exit 0

    current_ssid="$(active_ssid)"
    if [[ -n "${secondary_ssid}" && "${current_ssid}" == "${secondary_ssid}" ]]; then
      echo "Wi-Fi connected to secondary Vokrr Wi-Fi network; primary is not visible yet."
      exit 0
    fi

    sleep "${SCAN_INTERVAL_SECONDS}"
  done

  # Final attempt lets NetworkManager try even if the AP was hidden or missed in scan results.
  nmcli connection up "vokrr-primary-wifi" ifname "${WIFI_IFACE}" >/dev/null 2>&1 && {
    echo "Connected to primary Vokrr Wi-Fi network."
    exit 0
  }
  nmcli connection up "vokrr-secondary-wifi" ifname "${WIFI_IFACE}" >/dev/null 2>&1 && {
    echo "Connected to secondary Vokrr Wi-Fi network."
    exit 0
  }

  echo "Configured Vokrr Wi-Fi networks; neither SSID is currently visible."
}

main "$@"
