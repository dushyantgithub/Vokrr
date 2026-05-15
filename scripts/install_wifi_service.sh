#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "[!] Please run as root: sudo ./scripts/install_wifi_service.sh" >&2
  exit 1
fi

APP_DIR="${VOKRR_APP_DIR:-/home/dushyant/apps/Vokrr}"

chmod 0755 "${APP_DIR}/scripts/configure_wifi_networks.sh"
install -m 0644 "${APP_DIR}/infra/systemd/vokrr-wifi.service" /etc/systemd/system/vokrr-wifi.service
install -m 0644 "${APP_DIR}/infra/systemd/vokrr-stack.service" /etc/systemd/system/vokrr-stack.service
install -m 0644 "${APP_DIR}/infra/systemd/vokrr-kiosk.service" /etc/systemd/system/vokrr-kiosk.service

systemctl daemon-reload
systemctl enable vokrr-wifi.service
systemctl start vokrr-wifi.service
systemctl restart vokrr-stack.service || true
systemctl restart vokrr-kiosk.service || true

echo "Vokrr Wi-Fi service installed and started."
