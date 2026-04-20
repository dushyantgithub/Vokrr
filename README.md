# Quantum Home

Local-first smart home control system for Raspberry Pi 4 with Home Assistant as the integration engine, a custom FastAPI backend, a React touchscreen UI, and a local voice command path.

## Current Build

This repository now contains the Phase 1/2 foundation:

- Docker Compose stack for Home Assistant, backend, frontend, and voice intent bridge.
- FastAPI backend with Home Assistant REST/WebSocket client, normalized rooms/devices, actions, health checks, and frontend realtime WebSocket.
- React/Vite touchscreen UI optimized for the 1024x600 Waveshare display.
- Config-driven room/device mapping in `home-assistant/config/devices.yaml`.
- Kiosk and deployment docs for the Raspberry Pi.

## Quick Start On The Pi

```bash
cd ~/Projects/quantum-home
cp .env.example .env
```

Edit `.env` and set:

- `HOME_ASSISTANT_TOKEN` after creating a long-lived access token in Home Assistant.
- `APP_USERNAME`, `APP_PASSWORD`, and `APP_AUTH_SECRET` for the Quantum Home app login.

Keep `HOME_ASSISTANT_URL=http://localhost:8123` for the Docker Compose stack because the backend runs on host networking.

Start the stack:

```bash
docker compose -f infra/docker-compose.yml up -d --build
```

Open:

- Home Assistant: `http://quantum-home.local:8123`
- Quantum Home UI: `http://quantum-home.local:3000`
- Backend API docs: `http://quantum-home.local:8080/docs`

Use the Quantum Home app username/password from `.env` to sign in to the custom UI. Home Assistant credentials are only for Home Assistant administration and integration setup.

## Development

Backend:

```bash
cd backend
python3 -m venv .venv
. .venv/bin/activate
pip install -e ".[dev]"
uvicorn app.main:app --reload --port 8080
```

Frontend:

```bash
cd frontend
npm install
npm run dev -- --host 0.0.0.0
```

## Device Mapping

Home Assistant discovers the real entities. Quantum Home maps those entity IDs to stable rooms/devices in `home-assistant/config/devices.yaml`.

Use the backend discovery endpoint after Home Assistant is configured:

```bash
curl http://quantum-home.local:8080/api/ha/entities
```

Then replace the example entity IDs in `home-assistant/config/devices.yaml`.

## iOS App Plan

The iOS app will use the same backend as the touchscreen UI:

- First launch asks for the Quantum Home server address, initially `http://quantum-home.local:8080`.
- User signs in with the Quantum Home app username/password.
- The app stores the returned token in Keychain.
- Rooms, devices, actions, and realtime updates come from the backend, not directly from Home Assistant.
