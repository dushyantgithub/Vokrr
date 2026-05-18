# Hardware and Accessories

This document describes the hardware setup currently targeted by Vokrr. Items marked TODO need physical confirmation during final handoff.

## Primary Host

| Item | Current assumption |
| --- | --- |
| Computer | Raspberry Pi 4B |
| Memory | 8 GB |
| Storage | microSD or SSD supported by Raspberry Pi OS |
| Network | Wi-Fi configured by NetworkManager through `vokrr-wifi.service`; Ethernet also works |
| OS | Raspberry Pi OS 64-bit with a graphical session for the Qt kiosk |

## Display and Touch

| Item | Current setup |
| --- | --- |
| Display | Official Raspberry Pi 7-inch touchscreen |
| Resolution | 800x480 at 60 Hz |
| Connector | DSI ribbon cable |
| Touch | DSI/I2C touch handled by Raspberry Pi OS input stack |

The setup script configures the official DSI panel and removes older Waveshare HDMI 1024x600 overrides:

```bash
sudo PI_USER=$USER ./scripts/phase0_setup.sh
sudo reboot
```

The kiosk launcher maps known touch device names to the active DSI output with `xinput map-to-output`.

## Camera

The Qt UI uses Qt Multimedia `MediaDevices`, `Camera`, `CaptureSession`, and `VideoOutput` to show the default local camera input.

Known or requested camera hardware:

| Item | Status |
| --- | --- |
| Raspberry Pi Camera Module Rev 1.3 / 5MP | Supported by Raspberry Pi OS if enabled and visible to Qt Multimedia. TODO / Needs confirmation: whether this is the active camera. |
| USB camera | Supported when visible as the default video input. Current voice microphone health has shown a USB device named `USB Device 0x46d:0x825`; this may be a Logitech webcam. |

Camera checks:

```bash
libcamera-hello --list-cameras
v4l2-ctl --list-devices
```

Install helpers if needed:

```bash
sudo apt install -y libcamera-apps v4l-utils
```

## Audio Output

Vokrr detects an ALSA playback device and writes `backend/data/audio-output.env` for the Spotify Connect and voice-listener containers.

Priority in `scripts/select_audio_output.sh`:

1. Aux/headphone/analog playback
2. Non-webcam USB audio playback
3. HDMI only if `VOKRR_AUDIO_ALLOW_HDMI=1`
4. MAX98357A I2S fallback

Known or requested audio hardware:

| Item | Status |
| --- | --- |
| Adafruit MAX98357A I2S 3W Class D Amplifier Breakout Board | Configured as fallback through `dtoverlay=max98357a`. |
| AUX/headphone audio | Preferred automatically when detected. |
| 2030 cavity speaker / 8 ohm 2W | TODO / Needs confirmation: listed in handoff requirements but not detectable from repo. |
| INVENTO 2040 4 ohm 2W speaker | TODO / Needs confirmation: listed in handoff requirements but not detectable from repo. |

Audio checks:

```bash
aplay -l
scripts/select_audio_output.sh --test
speaker-test -D "$(grep '^VOICE_OUTPUT_DEVICE=' backend/data/audio-output.env | cut -d= -f2-)" -c2 -t sine -f 1000
```

## Microphone

The listener uses `sounddevice` and ALSA. `VOICE_INPUT_DEVICE` can pin a specific device name.

Known current setting from deployment:

```bash
VOICE_INPUT_DEVICE=USB Device 0x46d:0x825
```

Microphone checks:

```bash
arecord -l
python3 - <<'PY'
import sounddevice as sd
print(sd.query_devices())
PY
```

## Power, Case, UPS

No committed code requires a specific power supply, case, or UPS HAT.

Recommended baseline:

- Official Raspberry Pi USB-C power supply or equivalent stable supply.
- Case with airflow for 24/7 use.
- Optional UPS HAT only if it is already configured at the OS level.

TODO / Needs confirmation:

- Exact power supply model.
- Any UPS HAT or safe-shutdown wiring.
- Final enclosure/case model.

## Raspberry Pi Configuration Notes

`scripts/phase0_setup.sh` configures:

- Base packages and Qt kiosk dependencies
- Docker and Docker Compose plugin
- UFW with SSH allowed
- Official DSI display mode: `video=DSI-1:800x480@60`
- KMS overlay: `dtoverlay=vc4-kms-v3d`
- Onboard/aux audio: `dtparam=audio=on`
- MAX98357A I2S fallback: `dtoverlay=max98357a`
- Vokrr systemd unit installation

Verify boot config:

```bash
grep -E 'vc4-kms-v3d|max98357a|dtparam=audio' /boot/firmware/config.txt /boot/config.txt 2>/dev/null
tr ' ' '\n' < /boot/firmware/cmdline.txt 2>/dev/null | grep 'video=DSI'
```

