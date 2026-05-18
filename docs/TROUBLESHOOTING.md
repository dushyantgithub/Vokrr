# Troubleshooting

Start with:

```bash
scripts/health_check.sh
docker compose -f infra/docker-compose.yml ps
```

## Backend Cannot Reach Home Assistant

Check Home Assistant:

```bash
curl -sS http://localhost:8123/api/
curl -sS http://localhost:8080/api/system/health | python3 -m json.tool
```

Check env inside the backend:

```bash
docker compose -f infra/docker-compose.yml exec backend env | grep HOME_ASSISTANT
```

For the current host-networked stack, `HOME_ASSISTANT_URL` should normally be:

```bash
HOME_ASSISTANT_URL=http://localhost:8123
```

## Devices Missing or Not Updating

```bash
docker compose -f infra/docker-compose.yml logs --tail=120 backend
curl -sS http://localhost:8080/api/system/health
```

Refresh devices:

```bash
curl -X POST http://localhost:8080/api/devices/refresh \
  -H "Authorization: Bearer ${ACCESS_TOKEN}"
```

If a device was renamed/moved in Home Assistant, check:

```bash
curl -sS http://localhost:8080/api/ha/entities \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  | python3 -m json.tool
```

## Device State Mismatch

The backend reconciles with HA every `STATE_SYNC_INTERVAL_SECONDS` and on startup. If mismatch persists:

```bash
docker compose -f infra/docker-compose.yml restart backend
docker compose -f infra/docker-compose.yml logs -f --tail=100 backend
```

Look for:

```text
Initial Home Assistant state sync completed
```

## WebSocket Not Updating

Check that the client has a valid access token and backend logs show an open WebSocket:

```bash
docker compose -f infra/docker-compose.yml logs --tail=120 backend | grep -i websocket
```

Restart kiosk:

```bash
sudo systemctl restart vokrr-kiosk.service
```

## App Not Starting on Boot

```bash
systemctl status vokrr-wifi.service --no-pager
systemctl status vokrr-stack.service --no-pager
systemctl status vokrr-kiosk.service --no-pager
journalctl -u vokrr-kiosk.service -b --no-pager
```

Common causes:

- Absolute paths in systemd units do not match the install path.
- Qt binary has not been built.
- Backend did not become healthy before kiosk timeout.
- No X11/Wayland graphical session is available.

## Kiosk or Fullscreen Issues

Run the kiosk script manually:

```bash
VOKRR_API_BASE=http://localhost:8080 scripts/start_qt_kiosk.sh
```

Run windowed:

```bash
VOKRR_QT_WINDOWED=1 VOKRR_API_BASE=http://localhost:8080 qt-frontend/build/vokrr-qt
```

Rebuild:

```bash
cmake -S qt-frontend -B qt-frontend/build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build qt-frontend/build
```

## Raspberry Pi Display Issues

Verify DSI mode:

```bash
tr ' ' '\n' < /boot/firmware/cmdline.txt 2>/dev/null | grep 'video=DSI'
grep -E 'vc4-kms-v3d|Waveshare|hdmi_cvt|framebuffer' /boot/firmware/config.txt /boot/config.txt 2>/dev/null
```

Re-run setup if old Waveshare/HDMI values remain:

```bash
sudo PI_USER=$USER ./scripts/phase0_setup.sh
sudo reboot
```

## Touch Issues

Check input devices:

```bash
xinput list
libinput list-devices
```

The kiosk launcher tries common Raspberry Pi touchscreen names and maps them to the DSI output. If touch is rotated, set:

```bash
VOKRR_TOUCH_ROTATION=180
```

Then restart:

```bash
sudo systemctl restart vokrr-kiosk.service
```

## Audio Not Playing

Detect output:

```bash
aplay -l
scripts/select_audio_output.sh --test
cat backend/data/audio-output.env
```

Restart audio services:

```bash
scripts/restart_audio_stack.sh
```

Check listener output device:

```bash
docker compose -f infra/docker-compose.yml exec voice-listener env | grep VOICE_OUTPUT_DEVICE
```

## MAX98357A I2S Amplifier Issues

Check boot config:

```bash
grep -E 'max98357a|dtparam=audio' /boot/firmware/config.txt /boot/config.txt 2>/dev/null
aplay -l
```

Expected fallback ALSA device:

```bash
plughw:CARD=MAX98357A,DEV=0
```

If it is missing, verify wiring and reboot after config changes.

## Camera Not Detected

```bash
libcamera-hello --list-cameras || true
v4l2-ctl --list-devices || true
```

Install tools:

```bash
sudo apt install -y libcamera-apps v4l-utils
```

If using a Pi Camera Module, ensure the ribbon cable is seated and camera support is enabled in Raspberry Pi OS. If using USB, confirm it appears under `/dev/video*`.

## Voice Listener Stuck Waiting for Wake Word

Health:

```bash
curl -sS http://localhost:8091/health | python3 -m json.tool
docker compose -f infra/docker-compose.yml logs --tail=120 voice-listener
```

Check microphone:

```bash
arecord -l
docker compose -f infra/docker-compose.yml exec voice-listener python - <<'PY'
import sounddevice as sd
print(sd.query_devices())
PY
```

Set `VOICE_INPUT_DEVICE` to the correct device name or index, then restart:

```bash
docker compose -f infra/docker-compose.yml up -d --force-recreate voice-listener
```

## Wake Word File or Porcupine Errors

Check:

```bash
ls -l wake-word/
docker compose -f infra/docker-compose.yml exec voice-listener env | grep PORCUPINE
```

Required:

- `PORCUPINE_API_KEY`
- `PORCUPINE_KEYWORD_PATH=/wake-word/Jarvis_en_raspberry-pi_v4_0_0.ppn`
- Wake-word file mounted into the container.

## NVIDIA LLM/TTS Errors

Check keys:

```bash
docker compose -f infra/docker-compose.yml exec voice-listener env | grep -E 'NVIDIA|MAGPIE'
```

CLI test:

```bash
docker compose -f infra/docker-compose.yml run --rm --no-deps voice-listener \
  python -m services.voice_pipeline --text "what is the state of bedroom fan" --no-speak
```

Use `VOICE_KEEP_TTS_FILES=1` to keep generated wav files for debugging.

## Tuya Credential/API Issues

Current Vokrr does not call Tuya APIs directly. Troubleshoot Tuya in Home Assistant:

1. Confirm the device works in Home Assistant.
2. Confirm the entity appears in `/api/states`.
3. Refresh/import devices in Vokrr.

If Home Assistant cannot control the Tuya device, fix the HA integration first.

## Spotify Issues

Check credentials:

```bash
curl -sS http://localhost:8080/api/spotify/auth-url \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  | python3 -m json.tool
```

Check Spotify Connect:

```bash
docker compose -f infra/docker-compose.yml logs --tail=100 spotify-connect
docker compose -f infra/docker-compose.yml ps spotify-connect
```

## Permission Issues

Common fixes:

```bash
sudo usermod -aG docker $USER
sudo usermod -aG audio $USER
newgrp docker
```

For systemd path issues, inspect:

```bash
systemctl cat vokrr-stack.service
systemctl cat vokrr-kiosk.service
```

