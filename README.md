# Vokrr

Local-first smart home control system for Raspberry Pi 4/5 with Home Assistant as the integration engine, a custom FastAPI backend, a native Qt/QML touchscreen console, and a local voice command pipeline.

## Current Build

The repository contains a working end-to-end stack:

- **Docker Compose stack** for Home Assistant, backend, and voice services.
- **FastAPI backend** with Home Assistant REST/WebSocket client, normalized rooms/devices, device actions, scenes/routines, health checks, and a realtime WebSocket hub for native clients.
- **Qt/QML touchscreen console** optimized for the official 7-inch Raspberry Pi DSI touch display at 800x480, featuring:
  - Native Qt Quick rendering instead of a browser shell.
  - Dashboard, device grid, routines, activity, news, and settings views.
  - Local kiosk auto-login through `POST /api/auth/kiosk`.
  - Live REST + WebSocket updates from the backend.
  - A `Jarvis` status bar showing idle/listening/processing/STT transcript states.
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
- Backend API docs: `http://vokrr.local:8080/docs`

Use the Vokrr bootstrap admin credentials from `.env` to sign in initially. Home Assistant credentials are only for Home Assistant administration and integration setup. Kiosk hosts (`localhost`, `127.0.0.1`, `::1`) auto-login via `POST /api/auth/kiosk`.

Build the native Qt console:

```bash
cmake -S qt-frontend -B qt-frontend/build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build qt-frontend/build
```

To make the stack and kiosk come back automatically after a Raspberry Pi reboot, install and enable the bundled systemd units:

```bash
sudo PI_USER=$USER ./scripts/phase0_setup.sh
sudo cp infra/systemd/vokrr-stack.service /etc/systemd/system/
sudo cp infra/systemd/vokrr-kiosk.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now vokrr-stack.service
sudo systemctl enable --now vokrr-kiosk.service
```

The setup script removes the old Waveshare HDMI 1024×600 timing overrides and sets the official DSI panel to `800x480@60`. Reboot after running it so Raspberry Pi firmware and KMS pick up the display change.

## Remote Access

The recommended remote-access path is Cloudflare Tunnel, not direct router exposure. This is especially important on CGNAT-backed ISPs where port forwarding cannot work reliably.

- Public API hostname: `https://api.vokrr.com`
- Tunnel runtime: Docker Compose `cloudflared` service under the `cloudflare` profile
- Setup guide: [docs/deployment/cloudflare-tunnel.md](./docs/deployment/cloudflare-tunnel.md)

The iOS app and any future external clients should use only the backend hostname. Do not expose Home Assistant directly.

## Native Console Architecture

The touchscreen console lives in `qt-frontend/`:

- `src/main.cpp` hosts the QML scene in a fullscreen Qt Quick window.
- `qml/App.qml` talks directly to the backend REST endpoints and `/ws` WebSocket.
- `scripts/start_qt_kiosk.sh` waits for the backend and display session, then launches `qt-frontend/build/vokrr-qt`.
- `infra/systemd/vokrr-kiosk.service` starts the native console after LightDM and the Docker backend stack.

## Voice Commands

Templates are declared in `home-assistant/config/commands.yaml` under `intents.*.templates`. Examples:

- `turn on {target}` / `turn off {target}` / `toggle {target}` (device or room).
- `set {target} to {percent} percent` (brightness / percentage-capable devices).
- `make {target} warm` / `white` / `cool` (color-capable lights).
- `show me latest news`, `show the news`, `open news`, `go to news`, `latest news`, `news` → triggers a `navigate` action with `view: News`, and the Qt console switches tabs.

Matching is case-insensitive, strips punctuation and filler prefixes (`"hey"`, `"okay"`, `"jarvis"`, `"please"`, `"could you"`, etc.), and falls back to space-folded comparison so STT outputs like `"tube light"` still match the registry name `"Tubelight"`.

Each voice command pushes a `voice.command` event over the backend WebSocket; the Qt console uses it to drive the Jarvis status bar, push notifications for `command_error` / `error`, and switch views when the response contains a `navigate` field.

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

Qt/QML console:

```bash
cmake -S qt-frontend -B qt-frontend/build -G Ninja -DCMAKE_BUILD_TYPE=Debug
cmake --build qt-frontend/build
VOKRR_QT_WINDOWED=1 qt-frontend/build/vokrr-qt
```

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
