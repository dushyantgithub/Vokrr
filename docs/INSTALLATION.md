# Installation Guide

This guide installs Vokrr on a new Raspberry Pi.

## 1. Flash Raspberry Pi OS

Use Raspberry Pi Imager:

1. Choose Raspberry Pi OS 64-bit with Desktop.
2. Set hostname, for example `vokrr`.
3. Enable SSH.
4. Configure Wi-Fi if you want first boot on Wi-Fi.
5. Set a strong user password.
6. Flash the microSD/SSD and boot the Pi.

SSH in:

```bash
ssh <user>@vokrr.local
```

## 2. Clone the Repository

The provided systemd files currently assume:

```text
/home/dushyant/apps/Vokrr
```

For a different user/path, update every absolute path in `infra/systemd/*.service` and scripts that reference that path.

```bash
mkdir -p ~/apps
cd ~/apps
git clone <repo-url> Vokrr
cd Vokrr
```

## 3. Install OS Packages and Configure Pi Hardware

Run:

```bash
sudo PI_USER=$USER ./scripts/phase0_setup.sh
sudo reboot
```

This installs base packages, Docker, Qt kiosk packages, UFW, display configuration, audio configuration, and systemd unit files.

After reboot, verify:

```bash
docker --version
docker compose version
aplay -l
xinput list || true
```

## 4. Configure Environment

```bash
cp .env.example .env
cp .env.example scripts/.env
openssl rand -hex 32
```

Edit both `.env` and `scripts/.env`:

```bash
nano .env
nano scripts/.env
```

Required values:

- `HOME_ASSISTANT_TOKEN`
- `APP_BOOTSTRAP_ADMIN_USERNAME`
- `APP_BOOTSTRAP_ADMIN_PASSWORD`
- `APP_AUTH_SECRET`

Voice values if enabled:

- `VOICE_LISTENER_ENABLED=1`
- `PORCUPINE_API_KEY`
- `VOICE_INPUT_DEVICE`
- `NVIDIA_API_KEY` or `NVIDIA_BUILD_API_KEY`

Spotify values if enabled:

- `SPOTIFY_APP_CLIENT_ID`
- `SPOTIFY_APP_CLIENT_SECRET`
- `SPOTIFY_REDIRECT_URI`

See [ENVIRONMENT.md](ENVIRONMENT.md).

## 5. Start Home Assistant

```bash
docker compose -f infra/docker-compose.yml up -d homeassistant
docker compose -f infra/docker-compose.yml logs -f --tail=100 homeassistant
```

Open:

```text
http://vokrr.local:8123
```

Create the Home Assistant admin account and add integrations/devices.

Create a long-lived access token in Home Assistant user profile and paste it into `.env` and `scripts/.env`:

```bash
HOME_ASSISTANT_TOKEN=<token>
HOME_ASSISTANT_URL=http://localhost:8123
```

## 6. Start Vokrr Services

```bash
docker compose -f infra/docker-compose.yml up -d --build
docker compose -f infra/docker-compose.yml ps
```

Health checks:

```bash
curl -sS http://localhost:8080/api/system/health
curl -sS http://localhost:8091/health
```

## 7. Build and Start the Qt UI

```bash
cmake -S qt-frontend -B qt-frontend/build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build qt-frontend/build
```

Windowed test:

```bash
VOKRR_QT_WINDOWED=1 VOKRR_API_BASE=http://localhost:8080 qt-frontend/build/vokrr-qt
```

Fullscreen:

```bash
VOKRR_API_BASE=http://localhost:8080 qt-frontend/build/vokrr-qt
```

## 8. Enable Production Autostart

```bash
sudo ./scripts/install_wifi_service.sh
sudo systemctl enable --now vokrr-stack.service
sudo systemctl enable --now vokrr-kiosk.service
```

Check:

```bash
systemctl status vokrr-stack.service --no-pager
systemctl status vokrr-kiosk.service --no-pager
```

## 9. Configure Devices

Vokrr can import Home Assistant devices automatically on backend startup and through:

```bash
POST /api/devices/refresh
```

Manual/static mappings live in:

```text
home-assistant/config/devices.yaml
```

Discover HA entities:

```bash
TOKEN=$(curl -sS http://localhost:8080/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"change-this-admin-password"}' \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])')

curl -sS http://localhost:8080/api/ha/entities \
  -H "Authorization: Bearer ${TOKEN}" \
  | python3 -m json.tool
```

## 10. Configure Home Assistant or Tuya Devices

Home Assistant is the integration layer. For Tuya:

1. Add Tuya/local-tuya in Home Assistant.
2. Confirm entities appear in Home Assistant.
3. Import/sync them in Vokrr.

The current Vokrr backend does not call Tuya cloud APIs directly.

## 11. Test Hardware

Audio:

```bash
scripts/select_audio_output.sh --test
scripts/restart_audio_stack.sh
```

Microphone:

```bash
arecord -l
docker compose -f infra/docker-compose.yml exec voice-listener python - <<'PY'
import sounddevice as sd
print(sd.query_devices())
PY
```

Camera:

```bash
libcamera-hello --list-cameras || true
v4l2-ctl --list-devices || true
```

Touch/display:

```bash
xrandr --query || true
xinput list || true
journalctl -u vokrr-kiosk.service -b --no-pager
```

Device control:

```bash
curl -sS http://localhost:8080/api/devices \
  -H "Authorization: Bearer ${TOKEN}" \
  | python3 -m json.tool
```

