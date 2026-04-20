# Quantum Home – Foundation Plan

## 1. Home Assistant Installation Method
- **Recommendation:** Home Assistant Container managed through Docker Compose on Raspberry Pi OS Lite (64-bit).
- **Why not Home Assistant OS/Supervised:** Those variants assume the Pi is fully dedicated to Home Assistant and restrict the ability to run custom containers/UIs/voice stack alongside HA under our control. We need a flexible platform hosting FastAPI, React UI assets, wake-word/STT/TTS services, and custom orchestration, so we cannot surrender host management to Home Assistant OS.
- **Benefits of the container approach:**
  - Uses the upstream Docker image maintained by Nabu Casa with ARM64 support, so we still receive official updates and integrations.
  - Compose lets us pin versions, manage environment files, share volumes, and control resource limits per service (critical on the Pi 4).
  - Keeps the host OS consistent with the rest of the stack (systemd/kiosk setup) and simplifies backup (bind-mounted config volumes).

## 2. Base Raspberry Pi OS / System Setup
- **OS Image:** Raspberry Pi OS Lite 64-bit (Debian Bookworm base). Lite keeps the footprint small while 64-bit is required by many modern Home Assistant and ML/voice components.
- **Flashing on workstation:**
  1. Install Raspberry Pi Imager.
  2. Select Raspberry Pi OS Lite (64-bit) → pick SD card → click the gear icon.
  3. Enable SSH, set username/password (e.g., `homeops`), configure Wi-Fi SSID/passphrase and locale, optionally pre-set hostname (`quantum-home`).
  4. Write the image and safely eject the card.
- **First boot checklist:**
  - Insert the card, connect Ethernet (preferred) or ensure Wi-Fi credentials were baked in, power on.
  - Discover IP via router UI or `ping quantum-home.local`.
  - SSH: `ssh homeops@quantum-home.local`.
  - Run `sudo raspi-config` if further locale/keyboard adjustments are needed; set GPU memory to 256 MB for kiosk graphics.
- **Wi-Fi & Static IP:**
  - To edit Wi-Fi manually, modify `/etc/wpa_supplicant/wpa_supplicant.conf`.
  - Prefer DHCP reservation on the router. If you must set static IP on the Pi, add to `/etc/dhcpcd.conf`:
    ```
    interface eth0
        static ip_address=192.168.1.50/24
        static routers=192.168.1.1
        static domain_name_servers=192.168.1.1
    ```

### 2.1 Waveshare 70H-1024600 Touchscreen Setup
The display uses HDMI for video (1024×600 @ 60 Hz) and USB for touch. Configure it immediately after the first system upgrade so the UI stack can run native resolution and accurate touch mapping.

1. **Enable the correct resolution** (`sudo nano /boot/config.txt`):
   ```
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
   ```
   - Save, exit, then reboot: `sudo reboot`.
2. **Confirm display timing:** after reboot run `tvservice -s` (should show 1024×600). If blank, ensure HDMI cable is connected before boot.
3. **Install touch/GUI dependencies:**
   ```bash
   sudo apt install -y xserver-xorg x11-xserver-utils xinput xinput-calibrator \
       chromium-browser openbox lightdm xserver-xorg-input-libinput
   ```
4. **Calibrate touch (only if touches do not line up):**
   ```bash
   export DISPLAY=:0
   sudo xinput_calibrator
   ```
   - Copy the generated `Section "InputClass"` snippet into `/etc/X11/xorg.conf.d/99-waveshare-touch.conf` (create directory if missing) to persist calibration.
5. **Ensure USB touch recognized:** `lsusb` should show a Waveshare/ILITEK device. Verify input: `xinput list` → note device name → `xinput test <id>`.
6. **Rotate orientation if required:**
   - For landscape kiosk, set `Option "TransformationMatrix" "1 0 0 0 1 0 0 0 1"` in the calibration file.
7. **Test end-to-end:** start X temporarily and open Chromium to confirm multi-touch/mouse interactions: `startx /usr/bin/chromium-browser --start-fullscreen`.

## 3. System Updates & Base Packages
Run immediately after first login.
```bash
sudo apt update
sudo apt full-upgrade -y
sudo rpi-eeprom-update -a
sudo reboot
sudo apt install -y git curl unzip htop tmux python3-pip python3-venv \
    build-essential pkg-config libssl-dev libffi-dev libatlas-base-dev \
    portaudio19-dev libportaudio2 libasound-dev jq cmake ufw
```
- GUI/touch prerequisites are already covered in Section 2.1.
- Enable firewall baseline:
  ```bash
  sudo ufw allow OpenSSH
  sudo ufw enable
  ```

## 4. Docker & Compose Installation
```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker homeops
sudo systemctl enable docker
sudo apt install -y docker-compose-plugin
```
Log out/in so the `homeops` user can run Docker without sudo.

## 5. Repository / Folder Structure
```
quantum-home/
├── backend/                  # FastAPI service
│   ├── app/
│   ├── tests/
│   └── pyproject.toml
├── frontend/                 # React + Vite UI
│   ├── src/
│   └── package.json
├── voice-pipeline/           # Wake-word, STT, TTS microservices
│   ├── wakeword/
│   ├── stt/
│   ├── intent/
│   └── tts/
├── home-assistant/           # compose config, secrets templates, automations
│   └── configuration/
├── infra/
│   ├── docker-compose.yml    # orchestrates HA + backend + voice + frontend runtime
│   ├── env/
│   └── systemd/              # kiosk + service units
├── docs/
│   ├── setup/
│   ├── deployment/
│   ├── troubleshooting/
│   └── README.md
├── scripts/                  # helper scripts (bootstrap, tests, health checks)
└── Makefile                  # top-level automation entry points
```

## 6. Service Architecture Overview
- **Home Assistant (Docker container):** runs integrations, exposes REST/WebSocket APIs. Mount `/homeops/quantum-home/home-assistant/config` for persistence. Home Assistant remains the device/integration engine and is not the primary UI.
- **Backend (FastAPI + async workers):** modules for local app authentication, device abstraction, HA client, intent handler, WebSocket broadcaster. Uses YAML/JSON metadata for rooms/devices and may add SQLite later for user/session metadata if needed.
- **Frontend (React/Vite):** kiosk web app talking to the backend via authenticated REST + WebSocket for realtime state.
- **iOS App (Swift/SwiftUI, planned):** native local-network client that discovers or accepts the Quantum Home server address, requires username/password login on first launch, stores the issued app token in Keychain, then displays the same rooms/devices/actions exposed by the backend.
- **Voice Pipeline:** wake-word engine (Porcupine/openWakeWord), recorder, STT (Vosk/Coqui), intent parser, TTS (Piper) as separate Python services communicating over gRPC/HTTP.
- **Shared infrastructure:** Compose-defined network, `.env` files for secrets, Docker logging routed to journald, optional systemd units for kiosk and Compose stack autostart.

### 6.1 Local Network Exposure & App Login
- Quantum Home is exposed on the local network through the Raspberry Pi hostname/IP:
  - Touchscreen/web UI: `http://quantum-home.local:3000`
  - Backend API: `http://quantum-home.local:8080`
  - Home Assistant admin/setup UI: `http://quantum-home.local:8123`
- Normal users should use the Quantum Home app login, not the Home Assistant UI. Home Assistant credentials remain for administrator setup/integrations only.
- The backend owns the Quantum Home username/password credentials via environment variables:
  - `APP_USERNAME`
  - `APP_PASSWORD`
  - `APP_AUTH_SECRET`
- Web UI and future iOS clients authenticate with `POST /api/auth/login`, receive a signed local token, and pass it to protected backend APIs with `Authorization: Bearer <token>`.
- WebSocket clients pass the same token when connecting so realtime state updates are limited to signed-in clients.
- This is local-first authentication for a trusted LAN. Before any internet exposure, add HTTPS, stronger user management, rate limiting, and a proper reverse proxy.

## 7. Phase 0 – Reset & Install Execution (In Progress)
Follow these steps now that the touchscreen is connected:

1. **Prep Workstation & Downloads**
   - Install Raspberry Pi Imager, gather Wi-Fi credentials, plan secure passwords.
2. **Wipe & Flash microSD** (per Section 2) ensuring hostname `quantum-home` and SSH enabled.
3. **Boot & Network**
   - Attach Waveshare HDMI + USB before powering on so the Pi negotiates the custom resolution.
   - SSH into the Pi, change default password, optionally create secondary admin user.
4. **Apply System Updates & Firmware** using commands from Section 3.
5. **Configure Touchscreen** using Section 2.1 steps immediately after the first reboot so calibration persists before kiosk setup.
6. **Install Base Tooling** (Section 3) and **Docker + Compose** (Section 4).
7. **Project Checkout**
   ```bash
   mkdir -p ~/Projects && cd ~/Projects
   git clone <repo-url> quantum-home
   cd quantum-home
   ```
8. **Hardware Verification**
   - Display/touch: `xinput list`, run Chromium fullscreen test.
   - Microphone: `arecord -l` then `arecord -d 5 test.wav`; playback with `aplay test.wav`.
   - Speaker: `speaker-test -c2 -twav` to confirm output.
9. **Security Baseline** already set with UFW; consider SSH key auth and disable password login once confident.

With Phase 0 actively underway per the checklist above, the Raspberry Pi will exit this phase with a clean OS, Waveshare touchscreen calibrated at 1024×600, Docker/Compose installed, security hardened, and the repository ready for subsequent phases (Home Assistant containerization, backend/frontend scaffolding, voice pipeline, kiosk autostart, etc.).

## 8. Phase 0 Automation Script
A helper script now lives at `scripts/phase0_setup.sh`. Run it locally on the Pi to execute the repeatable parts of Phase 0 (system upgrades, package install, HDMI block, Docker setup).

### Usage
```bash
cd ~/Projects/quantum-home
sudo PI_USER=$USER ./scripts/phase0_setup.sh
```
- `PI_USER` defaults to `homeops`; override if your login differs so the script can add you to the `docker` group.
- Script actions: `apt update/full-upgrade`, EEPROM refresh, installs base + kiosk packages, configures UFW for SSH, appends the Waveshare HDMI block to `/boot/config.txt` if missing, installs Docker + Compose.
- Reboot afterward to apply GPU/firmware changes.

### Manual steps that remain
1. Touch calibration (`xinput_calibrator`) and saving 99-waveshare conf if the pointer is offset.
2. Microphone/speaker verification commands.
3. Repository cloning (if not already done) and SSH key hardening.
4. Any environment-specific network/static-IP configurations beyond the defaults.

Once the script finishes and the Pi reboots cleanly, Phase 0 is considered complete and we can proceed to Phase 1 (Home Assistant deployment).

## 9. Added Scope – iOS App
The iOS app is a native companion client for the same local-first backend. It does not talk directly to Home Assistant.

### Requirements
1. First launch requires Quantum Home server address discovery or manual entry.
2. User signs in using the Quantum Home app username/password.
3. App stores the returned token in Keychain.
4. App loads rooms/devices from the backend.
5. App controls devices through the same backend action APIs used by the touchscreen UI.
6. App subscribes to realtime updates over backend WebSocket.
7. App handles offline/local-network unavailable states clearly.

### Recommended iOS Stack
- Swift + SwiftUI for UI.
- URLSession for REST calls.
- URLSessionWebSocketTask for realtime updates.
- Keychain for token storage.
- Bonjour/mDNS discovery later, with manual `http://quantum-home.local:8080` entry as the first implementation.
