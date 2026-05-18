# Developer Guide

## Folder Structure

```text
.
├── backend/                  # FastAPI backend
├── docs/                     # Maintainer and user documentation
├── home-assistant/config/    # Home Assistant config and Vokrr YAML registry
├── infra/                    # Docker Compose and systemd units
├── ios/                      # Generated iOS Xcode project
├── qt-frontend/              # Native Qt/QML kiosk
├── scripts/                  # Setup, health, kiosk, audio, Wi-Fi helpers
├── services/                 # Shared realtime voice pipeline services
└── voice-pipeline/           # Voice listener and legacy intent bridge containers
```

## Important Backend Modules

| Module | Purpose |
| --- | --- |
| `backend/app/main.py` | FastAPI app, CORS, lifespan startup/shutdown |
| `backend/app/api/routes.py` | REST and WebSocket API |
| `backend/app/core/config.py` | Pydantic environment settings |
| `backend/app/domain/models.py` | API/domain models |
| `backend/app/services/auth.py` | Users, JWTs, refresh tokens, activity log |
| `backend/app/services/home_assistant.py` | HA REST/WebSocket client |
| `backend/app/services/registry.py` | YAML/imported device registry |
| `backend/app/services/onboarding.py` | HA discovery/import persistence |
| `backend/app/services/device_service.py` | Device/room actions |
| `backend/app/services/state_sync.py` | HA live updates and reconciliation |
| `backend/app/services/intent.py` | Legacy text command parser |
| `backend/app/services/spotify.py` | Spotify OAuth and playback API |

## Device Abstraction Layer

The domain model is:

- `Room`
- `Device`
- `DeviceState`
- `Capability`
- `Scene`

Sources:

- Static YAML in `home-assistant/config/devices.yaml`
- Imported HA entities persisted in `backend/data/onboarding.db`

Controls are capability-based, not brand-specific. A Tuya switch, Matter light, or ESPHome fan is controlled only after it appears as a Home Assistant entity.

## API Architecture

All normal clients call the backend:

- Auth: `/api/auth/*`
- Admin: `/api/admin/*`
- Rooms/devices/scenes: `/api/rooms`, `/api/devices`, `/api/scenes`
- Home Assistant discovery: `/api/ha/entities`
- Spotify: `/api/spotify/*`
- Voice events/legacy commands: `/api/voice/*`
- WebSocket: `/ws?token=...`

Use `http://localhost:8080/docs` for generated OpenAPI docs.

## WebSocket Flow

1. Client logs in and receives `access_token`.
2. Client connects to `/ws?token=<access_token>`.
3. Backend validates the token.
4. Backend sends an initial `snapshot`.
5. Backend broadcasts updates from HA, device actions, scene runs, and voice events.

## Environment Variables

Use `.env.example` and [ENVIRONMENT.md](ENVIRONMENT.md). Backend settings are strongly typed in `backend/app/core/config.py`; voice services read environment directly with `os.getenv`.

## Adding a New Integration

Preferred pattern:

1. Add/pair the integration in Home Assistant.
2. Confirm the entity domain and attributes in `/api/states`.
3. If it is a new domain, add support in:
   - `backend/app/services/onboarding.py`
   - `backend/app/services/registry.py`
   - `backend/app/services/device_service.py`
   - `services/ha_service.py` for voice
4. Add UI icon/type handling in QML if needed.
5. Add tests for registry/import/control behavior.

Direct cloud-provider integrations should be added only when Home Assistant cannot handle the device.

## Adding a New Device Type

1. Add the type to `DeviceType` in `backend/app/domain/models.py`.
2. Add inference in `infer_device_type`.
3. Add capabilities in `infer_capabilities`.
4. Add service call behavior in `DeviceService`.
5. Add UI icon/layout support in `qt-frontend/qml/roomfinal`.
6. Add voice matching support in `services/ha_service.py` if voice should control it.
7. Add or update tests.

## Adding a New UI Screen or Component

1. Add a QML component under `qt-frontend/qml/`.
2. Register the QML file in `qt-frontend/CMakeLists.txt`.
3. Wire navigation/state in `qt-frontend/qml/App.qml`.
4. Rebuild:
   ```bash
   cmake --build qt-frontend/build
   ```
5. Run windowed:
   ```bash
   VOKRR_QT_WINDOWED=1 qt-frontend/build/vokrr-qt
   ```

## Coding Conventions

- Python 3.11+.
- FastAPI route models should live in `domain/models.py`.
- Keep Home Assistant calls inside service classes.
- Keep UI backend calls in `App.qml` or focused QML components.
- Prefer capability checks before device actions.
- Do not commit secrets, databases, runtime caches, or generated audio files.

## Testing

Backend tests:

```bash
cd backend
python3 -m venv .venv
. .venv/bin/activate
pip install -e ".[dev]"
python -m pytest
```

Qt build:

```bash
cmake -S qt-frontend -B qt-frontend/build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build qt-frontend/build
```

Service health:

```bash
scripts/health_check.sh
```

Voice CLI:

```bash
docker compose -f infra/docker-compose.yml run --rm --no-deps voice-listener \
  python -m services.voice_pipeline --text "turn off bedroom lights" --no-speak
```

Manual verification:

- Login works.
- `/api/rooms` and `/api/devices` return current HA state.
- Device toggle updates HA and broadcasts `device.updated`.
- Restarted backend performs startup sync.
- Kiosk reconnects WebSocket after backend restart.
- Voice resets after one command or 10 seconds.

