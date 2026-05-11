#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SERVICE_SOURCE="${PROJECT_ROOT}/infra/systemd/vokrr-ui.service"
SERVICE_TARGET="/etc/systemd/system/vokrr-ui.service"

if [[ ! -f "${SERVICE_SOURCE}" ]]; then
  echo "Missing service file: ${SERVICE_SOURCE}" >&2
  exit 1
fi

sudo cp "${SERVICE_SOURCE}" "${SERVICE_TARGET}"
sudo systemctl daemon-reload
sudo systemctl enable --now vokrr-ui.service
sudo systemctl status --no-pager vokrr-ui.service
