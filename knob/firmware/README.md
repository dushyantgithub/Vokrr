# Vokrr Smart Knob Firmware

Production firmware for the Viewe `UEDX48480021-MD80ET` smart knob described in
`../Smart Knob.pdf`. It targets the ESP32-S3, 480x480 round ST7701S display,
CST826 touch controller, EC35 rotary encoder, and encoder push switch.

## Implemented screens

The runtime intentionally contains only the screens in `../Vokrr Knob.html`:

- Rooms carousel with device and active-device counts
- Devices carousel with live on/off, availability, and reported power state

The rotary encoder moves through the current carousel. A short press opens a
room or toggles its selected device. A long press returns to rooms. The center
ring and back button also support touch.

The room and device topology is fixed in firmware. At startup the knob opens a
secure Vokrr connection before the RGB display starts, and one initial
`GET /api/rooms` resolves backend IDs and current states. That connection is
reused to poll only the selected room every 10 seconds. Device actions use
`POST /api/devices/{id}/toggle` on the network loop, while input and rendering
stay on a separate UI task so network latency cannot block the encoder or
screen. Unchanged status responses do not redraw the UI. The firmware refreshes
expiring access tokens, preserves the selected room/device, rolls back failed
optimistic updates, and blocks actions for unavailable devices. If Wi-Fi or the
secure session is lost, the controller restarts once and restores the connection
before the display workload starts again.

## Mapped topology

- Living Room: Bulb, Fan, Socket, Tubelight
- Kitchen: Left Bulb, Right Bulb
- Gaming Room: Tubelight, Socket, Fan, Bulb, Tubelight
- Bedroom: Tubelight, Aircon Socket, Bulb, Fan, Socket, Tubelight
- Bathroom: Geyser
- Dining Room: Tubelight, Bulb

Only exact case-insensitive room and device name matches are shown. Duplicate
names, such as the two Tubelight entries, map to separate backend devices in
their backend order. Missing configured devices are skipped rather than replaced
with unrelated devices.

## Configure

Use a dedicated non-admin Vokrr user for the knob. Add these settings to the
repository `.env` using `knob.env.example` as the reference:

```dotenv
KNOB_WIFI_SSID=HomeWifi
KNOB_WIFI_PASSWORD=replace-me
KNOB_API_BASE=http://192.168.1.17:8080
KNOB_USERNAME=smart-knob
KNOB_PASSWORD=replace-me
KNOB_TIMEZONE=IST-5:30
```

`KNOB_API_BASE` must be reachable from the ESP32. Do not use `localhost` unless
the backend is running on the knob itself, which is not the normal deployment.

Generate the ignored C header from the environment:

```bash
cd knob/firmware
python3 scripts/generate_config.py
```

The generator can also use the existing ignored
`../.secrets/smart-knob-password` file. It never prints secret values and writes
`src/config_private.h` with owner-only permissions. Do not commit that file.

## Build and flash

Install PlatformIO, connect the board over USB, then run:

```bash
cd knob/firmware
pio run -e BOARD_VIEWE_UEDX48480021_MD80ET
pio run -e BOARD_VIEWE_UEDX48480021_MD80ET --target upload
pio device monitor --baud 115200
```

The image is written to
`.pio/build/BOARD_VIEWE_UEDX48480021_MD80ET/firmware.bin`. PlatformIO detects the
connected serial port automatically. To select one explicitly, add
`--upload-port /dev/cu.usbmodem101` on macOS or `--upload-port /dev/ttyACM0` on
Linux.

## Runtime states

- `WIFI OFFLINE`: Wi-Fi reconnects in the background every 12 seconds.
- `SYNCING WITH VOKRR`: Wi-Fi is up and authentication/data sync is in progress.
- `CONNECTION LOST`: the last backend request failed; center press retries.
- `UNAVAILABLE`: the device cannot be controlled until Home Assistant reports a
  valid state.

Power is displayed only when Home Assistant reports a numeric power attribute.
The firmware does not invent wattage estimates.
