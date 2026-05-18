# Raspberry Pi Deployment

This is a focused deployment reference for the production Raspberry Pi. For a full clean install, use [../INSTALLATION.md](../INSTALLATION.md).

## Production Layout

Current systemd files assume:

```text
/home/dushyant/apps/Vokrr
```

If the repo is installed elsewhere, update all absolute paths in:

- `infra/systemd/vokrr-wifi.service`
- `infra/systemd/vokrr-stack.service`
- `infra/systemd/vokrr-kiosk.service`
- scripts that reference the install path

## Install Packages and Hardware Config

```bash
sudo PI_USER=$USER ./scripts/phase0_setup.sh
sudo reboot
```

This configures:

- Official Raspberry Pi DSI display at `800x480@60`
- KMS graphics
- Onboard/aux audio
- MAX98357A I2S fallback
- Docker and Compose plugin
- Qt kiosk dependencies
- Vokrr systemd unit files

## Configure Environment

```bash
cp .env.example .env
cp .env.example scripts/.env
nano .env
nano scripts/.env
```

Minimum required:

```bash
HOME_ASSISTANT_TOKEN=your-home-assistant-token
APP_BOOTSTRAP_ADMIN_USERNAME=admin
APP_BOOTSTRAP_ADMIN_PASSWORD=use-a-long-unique-password
APP_AUTH_SECRET=use-a-64-character-random-secret
```

Generate the secret:

```bash
openssl rand -hex 32
```

## Start Services

```bash
docker compose -f infra/docker-compose.yml up -d --build
docker compose -f infra/docker-compose.yml ps
```

Local endpoints:

- Backend: `http://localhost:8080`
- Home Assistant: `http://localhost:8123`
- Voice listener: `http://localhost:8091/health`

## Build and Enable Kiosk

```bash
cmake -S qt-frontend -B qt-frontend/build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build qt-frontend/build
sudo ./scripts/install_wifi_service.sh
sudo systemctl enable --now vokrr-stack.service
sudo systemctl enable --now vokrr-kiosk.service
```

Check:

```bash
systemctl status vokrr-stack.service --no-pager
systemctl status vokrr-kiosk.service --no-pager
journalctl -u vokrr-kiosk.service -b --no-pager
```

## Remote Access

Use Cloudflare Tunnel for remote access and expose only the backend. Home Assistant should remain private.

See [cloudflare-tunnel.md](cloudflare-tunnel.md).

## Verification

```bash
scripts/health_check.sh
curl -sS http://localhost:8080/api/system/health | python3 -m json.tool
curl -sS http://localhost:8091/health | python3 -m json.tool
```
