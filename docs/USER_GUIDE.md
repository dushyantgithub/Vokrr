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

Open **Rooms**, select a room, and use the switch on each device card. **All Off** turns off every controllable device in that room. Changes appear immediately while the backend waits for Home Assistant confirmation; a failed command is rolled back and reported.

Color-capable lights show their current color as a swatch. Tap the swatch to choose warm, neutral, cool, or RGB colors and adjust brightness. The card border, swatch, and state label follow the latest selected or reported light color.

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

The Qt UI receives `snapshot` and `device.updated` events over the backend WebSocket. It also polls while the realtime connection is recovering.

## Voice Control

Wake word:

```text
Jarvis
```

Flow:

1. Say the wake word.
2. The Jarvis screen changes from standby to its active listening state.
3. Speak one command.
4. The listener records for up to 10 seconds, or stops earlier after silence.
5. Vokrr executes the command and resets to wake-word mode.

Examples:

- "Jarvis, turn on bedroom lights"
- "Jarvis, turn off living room fan"
- "Jarvis, what is the state of bedroom fan"

## Screen Navigation

The bottom bar opens Dashboard, Rooms, Health, Jarvis, and Settings. Settings contains wake-word status, theme preference, Home Assistant status, ring status, and display information. The Raspberry Pi kiosk starts fullscreen; on a non-800x480 display the interface scales uniformly without cropping.

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
