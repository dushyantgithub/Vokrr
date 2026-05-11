# Vokrr

Local-first smart home control system for Raspberry Pi 4/5 with Home Assistant as the integration engine, a custom FastAPI backend, a native Qt/QML touchscreen UI, and a local voice command pipeline.

## Current Build

The repository contains a working end-to-end stack:

- **Docker Compose stack** for Home Assistant, backend, frontend, and voice intent bridge.
- **FastAPI backend** with Home Assistant REST/WebSocket client, normalized rooms/devices, device actions, scenes/routines, health checks, and a realtime WebSocket hub for the frontend.
- **Native PySide6/QML touchscreen UI** under `vokrr_ui/`, optimized for the official Raspberry Pi 7 inch 800×480 touchscreen. It avoids Chromium, Electron, browser kiosk mode, WebViews, heavy blur, and video backgrounds.
- **Legacy React/Vite touchscreen UI** under `frontend/`, retained for reference and existing deployments, featuring:
  - Glass (frosted) UI across the sidebar, header, cards, dropdowns, and the login panel (`backdrop-filter` with translucent surfaces).
  - A lightweight full-viewport CSS backdrop instead of the previous WebGL aurora, to reduce GPU/CPU load on the Raspberry Pi.
  - A `Jarvis` status bar in the header showing idle/listening/processing/STT transcript states (replaces the old search bar).
  - A notifications bell with unread badge and a dropdown feed of recent events.
  - A `Settings` entry in the sidebar that expands to reveal `Hard refresh`, `Sign out`, and, for admin users, `Restart Raspberry Pi` plus a simple user-creation form.
  - A `News` tab that embeds [World Monitor](https://www.worldmonitor.app) inside the app via a reverse‑proxy (`/news-proxy/`) that strips `X-Frame-Options` / `Content-Security-Policy`.
- **Voice intent service** with YAML‑driven templates (`home-assistant/config/commands.yaml`), room/device name matching (including space‑folded fuzzy matching for STT outputs like "tube light" vs. "Tubelight"), and a `navigate` action that tells the UI which view to switch to.
- **Config‑driven room/device mapping** in `home-assistant/config/devices.yaml`.
- **Kiosk and deployment docs** for the Raspberry Pi.

## Quick Start On The Pi

```bash
cd ~/Projects/vokrr
cp .env.example .env
```

Edit `.env` and set:

- `HOME_ASSISTANT_TOKEN` after creating a long-lived access token in Home Assistant.
- `APP_BOOTSTRAP_ADMIN_USERNAME`, `APP_BOOTSTRAP_ADMIN_PASSWORD`, and `APP_AUTH_SECRET` for the initial Vokrr admin account.

Keep `HOME_ASSISTANT_URL=http://localhost:8123` for the Docker Compose stack because the backend runs on host networking.

Start the stack:

```bash
docker compose -f infra/docker-compose.yml up -d --build
```

Open:

- Home Assistant: `http://vokrr.local:8123`
- Vokrr UI: `http://vokrr.local:3000`
- Backend API docs: `http://vokrr.local:8080/docs`

Use the Vokrr bootstrap admin credentials from `.env` to sign in initially. Home Assistant credentials are only for Home Assistant administration and integration setup. Kiosk hosts (`localhost`, `127.0.0.1`, `::1`) auto-login via `POST /api/auth/kiosk`.

## Native Qt/QML Touchscreen UI

The native UI is the preferred Raspberry Pi display frontend. It runs with PySide6 and QML directly on the Pi, plays a startup WAV on every launch, and continues loading the interface if audio setup fails.

Install dependencies:

```bash
cd ~/Projects/vokrr
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
```

Configure Home Assistant access for the native UI:

```bash
export HA_TOKEN="your-long-lived-home-assistant-token"
```

The URL and token environment variable name live in `vokrr_ui/config/app_config.json`.

Run manually:

```bash
./scripts/start_vokrr_ui.sh
```

On a desktop session the script uses `QT_QPA_PLATFORM=xcb`. Without `DISPLAY`, it uses `eglfs` for a fullscreen Pi display path. The app forces an 800×480 fullscreen window and hides the cursor on Raspberry Pi touchscreen hardware.

Install as a boot service:

```bash
sudo nano infra/systemd/vokrr-ui.service
```

Adjust `User=`, `WorkingDirectory=`, and `ExecStart=` if your Pi checkout is not `/home/pi/Projects/vokrr`, then run:

```bash
./scripts/install_vokrr_ui_service.sh
```

The service starts after `graphical.target` and `sound.target`, restarts on failure, and plays the startup tune on every app launch or restart.

### MAX98357A Startup Audio

Enable I2S and test the Adafruit MAX98357A speaker path using [docs/raspberry_pi_audio_setup.md](./docs/raspberry_pi_audio_setup.md).

Quick audio checks:

```bash
speaker-test -t sine -f 1000 -c 2
aplay vokrr_ui/assets/audio/startup.wav
amixer set Digital 100%
```

The startup sound path is configured by `startup_sound` in `vokrr_ui/config/app_config.json`. Replace `vokrr_ui/assets/audio/startup.wav` with any WAV file to change it. If the file is missing or invalid, `vokrr_ui/services/audio.py` generates a simple mono five-second startup tone automatically.

To make the stack and kiosk come back automatically after a Raspberry Pi reboot, install and enable the bundled systemd units:

```bash
sudo cp infra/systemd/vokrr-stack.service /etc/systemd/system/
sudo cp infra/systemd/vokrr-kiosk.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now vokrr-stack.service vokrr-kiosk.service
```

## Remote Access

The recommended remote-access path is Cloudflare Tunnel, not direct router exposure. This is especially important on CGNAT-backed ISPs where port forwarding cannot work reliably.

- Public API hostname: `https://api.vokrr.com`
- Tunnel runtime: Docker Compose `cloudflared` service under the `cloudflare` profile
- Setup guide: [docs/deployment/cloudflare-tunnel.md](./docs/deployment/cloudflare-tunnel.md)

The iOS app and any future external clients should use only the backend hostname. Do not expose Home Assistant directly.

## Frontend Architecture

The frontend is a single-page Vite build served by nginx:

- Our own assets are emitted under `/app-assets/*` (configured via `build.assetsDir` in `vite.config.js`) so they never collide with upstream paths used by the News proxy.
- `nginx.conf` exposes:
  - `/` → SPA fallback.
  - `/news-proxy/*` → reverse proxy to `https://www.worldmonitor.app/` with response headers `X-Frame-Options`, `Content-Security-Policy`, `Strict-Transport-Security`, and the X-Origin policies stripped, plus `sub_filter` rules that rewrite absolute upstream URLs back to same-origin paths and neutralise the injected `<meta http-equiv="Content-Security-Policy">` tag.
  - `/assets/*`, `/favico/*`, `/_next/*`, `/api/*`, and other common root-relative paths used by the News upstream → forwarded to the same upstream so the embedded page can resolve its assets and XHR calls through the iframe's origin.

The background is now a pure CSS layered backdrop rather than a WebGL canvas so the kiosk can stay responsive on the Raspberry Pi while preserving the same dark/glass visual language.

## Voice Commands

Templates are declared in `home-assistant/config/commands.yaml` under `intents.*.templates`. Examples:

- `turn on {target}` / `turn off {target}` / `toggle {target}` (device or room).
- `set {target} to {percent} percent` (brightness / percentage-capable devices).
- `make {target} warm` / `white` / `cool` (color-capable lights).
- `show me latest news`, `show the news`, `open news`, `go to news`, `latest news`, `news` → triggers a `navigate` action with `view: News`, and the frontend switches tabs (useful for any future view as well).

Matching is case-insensitive, strips punctuation and filler prefixes (`"hey"`, `"okay"`, `"jarvis"`, `"please"`, `"could you"`, etc.), and falls back to space-folded comparison so STT outputs like `"tube light"` still match the registry name `"Tubelight"`.

Each voice command pushes a `voice.command` event over the backend WebSocket; the frontend uses it to drive the Jarvis status bar, push notifications for `command_error` / `error`, and switch views when the response contains a `navigate` field.

## Development

Backend:

```bash
cd backend
python3 -m venv .venv
. .venv/bin/activate
pip install -e ".[dev]"
uvicorn app.main:app --reload --port 8080
```

Run tests:

```bash
cd backend
. .venv/bin/activate
python -m pytest
```

Frontend:

```bash
cd frontend
npm install
npm run dev -- --host 0.0.0.0
```

The Vite dev server proxies `/api` and `/ws` to `http://localhost:8080`. The `/news-proxy/` path only exists in the production nginx build.

## Device Mapping

Home Assistant discovers the real entities. Vokrr maps those entity IDs to stable rooms/devices in `home-assistant/config/devices.yaml`.

Use the backend discovery endpoint after Home Assistant is configured:

```bash
curl http://vokrr.local:8080/api/ha/entities
```

Then replace the example entity IDs in `home-assistant/config/devices.yaml`.

## Backend API Surface

All endpoints sit under `/api/` on port 8080. Authenticated ones require a Bearer access token from `/api/auth/login`, `/api/auth/refresh`, or `/api/auth/kiosk`.

| Method | Path | Purpose |
| --- | --- | --- |
| POST | `/api/auth/login` | Sign in with a database-backed user account. Returns `{ access_token, refresh_token, expires_in, user }`. |
| POST | `/api/auth/refresh` | Rotate a refresh token and obtain a new access token pair. |
| POST | `/api/auth/logout` | Revoke the current refresh token. |
| GET  | `/api/auth/me` | Return the current authenticated user. |
| POST | `/api/auth/kiosk` | Localhost-only auto-login for the kiosk display. |
| POST | `/api/auth/register` | Optional self-registration when enabled with a registration code. |
| POST | `/api/admin/users` | Admin-only user creation endpoint. |
| POST | `/api/admin/system/restart` | Admin-only Raspberry Pi restart trigger. |
| GET  | `/api/admin/activity` | Admin-only audit log of auth and control actions. |
| GET  | `/api/system/health` | Backend + Home Assistant reachability. |
| GET  | `/api/ha/entities` | Raw Home Assistant entity list (for device mapping). |
| GET  | `/api/rooms` · `/api/rooms/{id}` | Rooms with nested device state. |
| POST | `/api/rooms/{id}/set` | Power a room on or off by updating all toggle-capable devices in that room. |
| GET  | `/api/devices` · `/api/devices/{id}` | Flat device list / single device. |
| POST | `/api/devices/{id}/toggle` | Toggle a device. |
| POST | `/api/devices/{id}/set` | Set brightness / percentage / color / state. |
| GET  | `/api/scenes` · `/api/scenes/{id}` | Scenes (routines). |
| POST | `/api/scenes/{id}/run` | Run a scene. |
| POST | `/api/voice/command` | Submit transcribed text for intent matching. Returns `{ understood, message, matched_device_ids, navigate? }`. |
| POST | `/api/voice/event` | Push a voice pipeline status update (`listening`, `processing`, ...). |
| GET  | `/api/voice/commands` | Enumerates templates and valid targets (for help / UI hints). |
| WS   | `/ws?token=...` | Realtime `snapshot`, `device.updated`, `voice.status`, `voice.command`, `scene.ran` events. |

## iOS App Plan

See `implementation_plan.md` §9 for the full plan. At a high level, the iOS app talks to the same backend as the touchscreen UI — never to Home Assistant directly — and mirrors the touchscreen's visual language (glass surfaces, audio-reactive aurora background, Jarvis status bar, notifications, rooms/devices, routines, activity, news).

The current native app implementation lives in [ios/Vokrr](./ios/Vokrr) and its setup/testing notes live in [docs/setup/ios-app.md](./docs/setup/ios-app.md).
