# Raspberry Pi Deployment

This deployment removes the need for Tailscale by exposing only the Vokrr backend to the internet over HTTPS. Home Assistant remains private on the Raspberry Pi and is reached locally by the backend.

## 1. Configure Environment

```bash
cp infra/env/backend.env.example scripts/.env
```

Edit `scripts/.env` and set:

```bash
HOME_ASSISTANT_TOKEN=your-home-assistant-token
APP_BOOTSTRAP_ADMIN_USERNAME=admin
APP_BOOTSTRAP_ADMIN_PASSWORD=use-a-long-unique-password
APP_AUTH_SECRET=use-a-64-character-random-secret
AUTH_DATABASE_PATH=/app/data/auth.db
APP_REGISTRATION_ENABLED=false
APP_REGISTRATION_CODE=
```

Use a strong random value for `APP_AUTH_SECRET`, for example:

```bash
openssl rand -hex 32
```

## 2. Start Services

```bash
docker compose -f infra/docker-compose.yml up -d --build
docker compose -f infra/docker-compose.yml logs -f --tail=100 backend
```

The backend auth database is persisted in `backend/data/auth.db`.

Local endpoints remain:

- `http://vokrr.local:3000` for the touchscreen/web UI.
- `http://127.0.0.1:8080` for the local backend.
- `http://vokrr.local:8123` for Home Assistant admin/setup on the LAN only.

## 3. Configure The Official 7-inch Display

The supported touchscreen is now the official Raspberry Pi 7-inch DSI capacitive touch display. It runs at `800x480@60` and should not need manual touch calibration on current Raspberry Pi OS.

Run the setup script on the Pi and reboot:

```bash
sudo PI_USER=$USER ./scripts/phase0_setup.sh
sudo reboot
```

This removes the old Waveshare HDMI `1024x600` timing and kernel mode from `/boot/firmware/config.txt` and `/boot/firmware/cmdline.txt`, then adds the DSI display mode. Keeping the old HDMI mode is the likely cause of cropped or missing screen edges after the hardware swap.

## 4. Publish The Backend Securely

If your ISP connection uses CGNAT, use Cloudflare Tunnel. That is the recommended setup for this project and the active `vokrr.com` deployment.

Follow [cloudflare-tunnel.md](./cloudflare-tunnel.md) and expose only the backend on `https://api.vokrr.com`.

If you have a real public IPv4 and want direct router exposure instead, you can still use Caddy with `infra/Caddyfile.example`, but that is a fallback path and it does not work behind CGNAT.

## 5. Optional User Registration

If you want to allow a second user to create an account without using the admin API, set:

```bash
APP_REGISTRATION_ENABLED=true
APP_REGISTRATION_CODE=one-time-invite-code
```

Then call:

```bash
curl -X POST https://api.vokrr.com/api/auth/register \
  -H 'Content-Type: application/json' \
  -d '{"username":"guest","password":"a-very-strong-password","registration_code":"one-time-invite-code"}'
```

Disable registration again after onboarding users.

## 6. Create Additional Users As Admin

Login first:

```bash
ACCESS_TOKEN=$(curl -s https://api.vokrr.com/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"use-a-long-unique-password"}' | python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])')
```

Create a user:

```bash
curl -X POST https://api.vokrr.com/api/admin/users \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"username":"iphone-user","password":"another-strong-password","is_admin":false}'
```

## 7. Kiosk Autostart

Install the systemd unit after Chromium and X are installed:

```bash
sudo cp infra/systemd/vokrr-kiosk.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now vokrr-kiosk.service
```

The kiosk unit starts after `graphical.target`/LightDM and the launcher now detects Wayland or X11 before opening Chromium. If you only see the Raspberry Pi wallpaper after reboot, check it with:

```bash
systemctl status vokrr-kiosk.service
journalctl -u vokrr-kiosk.service -b --no-pager
```
