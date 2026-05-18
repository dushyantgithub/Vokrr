# User Guide

## Signing In

The Raspberry Pi kiosk uses local kiosk login when started from localhost. Other clients sign in with the Vokrr username and password configured in `.env`.

Home Assistant credentials are separate and should be used only for Home Assistant administration.

## Creating or Setting Up a Home

Home Assistant owns the real home/integration setup:

1. Open `http://vokrr.local:8123`.
2. Add rooms/areas in Home Assistant.
3. Add integrations and pair devices.
4. Confirm entities appear and can be controlled in Home Assistant.
5. Open Vokrr and refresh/sync devices.

Vokrr imports Home Assistant entities into its own registry and presents them as rooms/devices.

## Adding Rooms

Preferred path:

1. Create or rename areas in Home Assistant.
2. Assign devices to those areas.
3. In Vokrr, use device refresh/sync.

Static rooms can also be declared in `home-assistant/config/devices.yaml`.

## Adding or Syncing Devices

Vokrr syncs devices from Home Assistant during backend startup. You can also trigger:

```bash
POST /api/devices/refresh
```

The backend filters out noisy entities such as child locks and switch backlights.

## Device Control

Supported device capabilities:

| Capability | What it does |
| --- | --- |
| `toggle` | Calls HA `turn_on`, `turn_off`, or `toggle` |
| `brightness` | Calls HA `turn_on` with brightness |
| `percentage` | Calls HA `set_percentage` |
| `color_temperature` | Calls HA `turn_on` with `color_temp_kelvin` |
| `color` | Calls HA `turn_on` with `rgb_color` |

Device and room actions are sent to the Vokrr backend, which validates the request and then calls Home Assistant.

## Home Assistant and Tuya Switching

All switching is routed through Home Assistant. If a device is Tuya-backed, pair it in Home Assistant first. Vokrr then controls the resulting Home Assistant entity.

The current codebase does not implement direct Tuya cloud switching.

## Device State Updates

State updates arrive through:

1. Home Assistant WebSocket `state_changed` events.
2. Backend periodic reconciliation every `STATE_SYNC_INTERVAL_SECONDS`.
3. Explicit sync after scenes and some device operations.
4. Startup sync with retries.

The Qt UI receives `snapshot` and `device.updated` events over the backend WebSocket.

## Voice Control

Wake word:

```text
Jarvis
```

Flow:

1. Say the wake word.
2. The voice pill changes from red `waiting for wake-word` to green `waiting for command`.
3. Speak one command.
4. The listener records for up to 10 seconds, or stops earlier after silence.
5. Vokrr executes the command and resets to wake-word mode.

Examples:

- "Jarvis, turn on bedroom lights"
- "Jarvis, turn off living room fan"
- "Jarvis, what is the state of bedroom fan"

## Spotify

If Spotify credentials are configured:

1. Open the Spotify panel in Vokrr.
2. Start OAuth login.
3. Complete login in the browser.
4. Use the Spotify Connect device named `Vokrr`.

## Troubleshooting Device Mismatch

If the UI state does not match the real device:

```bash
curl -sS http://localhost:8080/api/system/health
docker compose -f infra/docker-compose.yml logs --tail=100 backend
```

Then refresh devices from the UI or restart the backend:

```bash
docker compose -f infra/docker-compose.yml restart backend
```

If an entity was renamed in Home Assistant, refresh devices or update `home-assistant/config/devices.yaml`.

## Restarting Services

```bash
sudo systemctl restart vokrr-stack.service
sudo systemctl restart vokrr-kiosk.service
docker compose -f infra/docker-compose.yml restart backend voice-listener
```

Health check:

```bash
scripts/health_check.sh
```

