# Raspberry Pi I2S Audio Setup

Vokrr can play its startup sound through an Adafruit MAX98357A I2S 3W Class D amplifier and a mono 8 ohm speaker.

## Enable I2S

Edit the Raspberry Pi boot config file. Newer Raspberry Pi OS images usually use:

```bash
sudo nano /boot/firmware/config.txt
```

Older images may use:

```bash
sudo nano /boot/config.txt
```

Add:

```ini
dtoverlay=hifiberry-dac
```

If the onboard audio device conflicts with I2S output, disable it:

```ini
dtparam=audio=off
```

Reboot:

```bash
sudo reboot
```

## Test Audio

After reboot, confirm ALSA sees the I2S device:

```bash
aplay -l
```

Run a sine test:

```bash
speaker-test -t sine -f 1000 -c 2
```

Play the Vokrr startup sound from the repository root:

```bash
aplay vokrr_ui/assets/audio/startup.wav
```

Set software volume to maximum:

```bash
amixer set Digital 100%
```

Some Raspberry Pi images expose the mixer as `PCM` or `Master` instead of `Digital`. The native Vokrr UI tries `Digital`, then `PCM`, then `Master`.

## Mono Output

The MAX98357A is a mono amplifier. Stereo audio should be downmixed if needed. The generated Vokrr startup sound is mono, so it is safe for the MAX98357A path.
