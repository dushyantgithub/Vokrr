#!/usr/bin/env bash
set -euo pipefail

PI_USER="${PI_USER:-homeops}"
KIOSK_PACKAGES=(
  xserver-xorg x11-xserver-utils chromium-browser openbox lightdm
  xinput xinput-calibrator xserver-xorg-input-libinput
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

append_waveshare_block() {
  local config_file="/boot/firmware/config.txt"
  if [[ ! -f "${config_file}" ]]; then
    config_file="/boot/config.txt"
  fi
  local marker="# Waveshare-70H-1024600"
  if grep -q "${marker}" "${config_file}"; then
    echo "Waveshare HDMI settings already present; skipping";
    return
  fi
  cat <<'BLOCK' >> "${config_file}"
# Waveshare-70H-1024600
hdmi_force_hotplug=1
hdmi_group=2
hdmi_mode=87
hdmi_cvt=1024 600 60 6 0 0 0
max_framebuffer_width=1024
max_framebuffer_height=600
framebuffer_width=1024
framebuffer_height=600
hdmi_drive=1
dtoverlay=vc4-kms-v3d
# End Waveshare-70H-1024600
BLOCK
}

append_waveshare_cmdline_mode() {
  local cmdline_file="/boot/firmware/cmdline.txt"
  local video_mode="video=HDMI-A-2:1024x600M@60D"
  if [[ ! -f "${cmdline_file}" ]]; then
    cmdline_file="/boot/cmdline.txt"
  fi
  if grep -q "${video_mode}" "${cmdline_file}"; then
    echo "Waveshare kernel video mode already present; skipping";
    return
  fi
  sed -i "s/$/ ${video_mode}/" "${cmdline_file}"
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

run_step "Ensuring Waveshare HDMI timings configured"
append_waveshare_block
append_waveshare_cmdline_mode

run_step "Installing Docker engine and compose plugin"
install_docker

run_step "All Phase 0 automated steps complete"
echo "Reboot now to apply firmware/HDMI changes, then run 'xinput_calibrator' if touch needs calibration."
