#!/usr/bin/env bash
set -euo pipefail

PI_USER="${PI_USER:-homeops}"
KIOSK_PACKAGES=(
  xserver-xorg x11-xserver-utils openbox lightdm
  xinput xinput-calibrator xserver-xorg-input-libinput libinput-tools evtest
  cmake ninja-build g++ qt6-base-dev qt6-declarative-dev qt6-websockets-dev
  qml6-module-qtquick qml6-module-qtquick-window qml6-module-qtquick-controls
  qml6-module-qtquick-layouts qml6-module-qtwebsockets qml6-module-qtcore
)
BASE_PACKAGES=(
  git curl unzip htop tmux python3-pip python3-venv build-essential
  pkg-config libssl-dev libffi-dev libatlas-base-dev portaudio19-dev
  libportaudio2 libasound2-dev jq cmake ufw
)

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "[!] Please run as root (sudo ./phase0_setup.sh)" >&2
    exit 1
  fi
}

run_step() {
  local msg="$1"
  echo "\n==> ${msg}"
}

boot_config_file() {
  local config_file="/boot/firmware/config.txt"
  if [[ ! -f "${config_file}" ]]; then
    config_file="/boot/config.txt"
  fi
  printf '%s\n' "${config_file}"
}

boot_cmdline_file() {
  local cmdline_file="/boot/firmware/cmdline.txt"
  if [[ ! -f "${cmdline_file}" ]]; then
    cmdline_file="/boot/cmdline.txt"
  fi
  printf '%s\n' "${cmdline_file}"
}

configure_official_touch_display() {
  local config_file
  config_file="$(boot_config_file)"
  local cmdline_file
  cmdline_file="$(boot_cmdline_file)"
  local dsi_mode="video=DSI-1:800x480@60"

  sed -i '/# Waveshare-70H-1024600/,/# End Waveshare-70H-1024600/d' "${config_file}"
  sed -i -E \
    -e 's/[[:space:]]*hdmi_force_hotplug=1//g' \
    -e 's/[[:space:]]*hdmi_group=2//g' \
    -e 's/[[:space:]]*hdmi_mode=87//g' \
    -e 's/[[:space:]]*hdmi_cvt=1024 600 60 6 0 0 0//g' \
    -e 's/[[:space:]]*max_framebuffer_width=1024//g' \
    -e 's/[[:space:]]*max_framebuffer_height=600//g' \
    -e 's/[[:space:]]*framebuffer_width=1024//g' \
    -e 's/[[:space:]]*framebuffer_height=600//g' \
    -e 's/[[:space:]]*hdmi_drive=1//g' \
    "${config_file}"

  if ! grep -q '^dtoverlay=vc4-kms-v3d' "${config_file}"; then
    printf '\n# Official Raspberry Pi 7-inch DSI touch display\ndtoverlay=vc4-kms-v3d\n' >> "${config_file}"
  fi

  sed -i -E \
    -e 's/[[:space:]]*video=HDMI-A-[0-9]:1024x600M@60D//g' \
    -e 's/[[:space:]]*video=DSI-[0-9]:800x480@60(,[^[:space:]]*)?//g' \
    "${cmdline_file}"
  sed -i "s/$/ ${dsi_mode}/" "${cmdline_file}"

  echo "Configured official Raspberry Pi 7-inch DSI touch display at 800x480."
}

install_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
  else
    echo "Docker already installed; skipping"
  fi
  usermod -aG docker "${PI_USER}"
  apt install -y docker-compose-plugin
}

require_root
run_step "Updating apt package index"
apt update
run_step "Upgrading base system"
DEBIAN_FRONTEND=noninteractive apt full-upgrade -y

run_step "Updating Pi EEPROM"
rpi-eeprom-update -a || true

declare -a packages=("${BASE_PACKAGES[@]}" "${KIOSK_PACKAGES[@]}")
run_step "Installing base packages and kiosk prerequisites"
DEBIAN_FRONTEND=noninteractive apt install -y "${packages[@]}"

run_step "Enabling UFW for SSH baseline"
ufw allow OpenSSH || true
ufw --force enable

run_step "Ensuring official Raspberry Pi 7-inch DSI display configured"
configure_official_touch_display

run_step "Installing Docker engine and compose plugin"
install_docker

run_step "Installing Vokrr Wi-Fi boot configuration service"
chmod 0755 /home/dushyant/apps/Vokrr/scripts/configure_wifi_networks.sh
install -m 0644 /home/dushyant/apps/Vokrr/infra/systemd/vokrr-wifi.service /etc/systemd/system/vokrr-wifi.service
systemctl daemon-reload
systemctl enable vokrr-wifi.service

run_step "All Phase 0 automated steps complete"
echo "Reboot now to apply firmware/display changes. The official DSI touch display should not need manual calibration."
