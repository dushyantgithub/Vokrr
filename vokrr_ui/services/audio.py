from __future__ import annotations

import logging
import math
import subprocess
import time
import wave
from pathlib import Path

LOGGER = logging.getLogger(__name__)
PROJECT_ROOT = Path(__file__).resolve().parents[2]


def _project_path(path_value: str | Path) -> Path:
    path = Path(path_value)
    return path if path.is_absolute() else PROJECT_ROOT / path


def _duration_seconds(path: Path) -> float:
    with wave.open(str(path), "rb") as wav_file:
        frames = wav_file.getnframes()
        rate = wav_file.getframerate()
        return frames / float(rate)


def generate_startup_tone(path: Path, duration_seconds: float = 5.0) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    sample_rate = 44100
    amplitude = 0.42
    notes = [261.63, 329.63, 392.0, 523.25, 659.25]
    total_frames = int(sample_rate * duration_seconds)

    with wave.open(str(path), "wb") as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)
        frames = bytearray()
        for index in range(total_frames):
            note = notes[int(index / sample_rate) % len(notes)]
            envelope = min(1.0, index / 2205) * min(1.0, (total_frames - index) / 4410)
            sample = amplitude * envelope * math.sin(2.0 * math.pi * note * index / sample_rate)
            frames.extend(int(sample * 32767).to_bytes(2, byteorder="little", signed=True))
        wav_file.writeframes(bytes(frames))


def set_volume_max(config: dict | None = None) -> None:
    config = config or {}
    percent = int(config.get("startup_volume_percent", 100))
    controls = ("Digital", "PCM", "Master")

    for control in controls:
        command = ["amixer", "set", control, f"{percent}%"]
        try:
            subprocess.run(command, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
            LOGGER.info("Set ALSA volume using control %s", control)
            return
        except FileNotFoundError:
            LOGGER.warning("amixer is not installed; skipping software volume setup")
            return
        except subprocess.CalledProcessError as exc:
            LOGGER.debug("amixer control %s unavailable: %s", control, exc.stderr.strip())

    LOGGER.warning("No ALSA volume control accepted %s%%", percent)


def play_startup_sound(config: dict | None = None) -> None:
    config = config or {}
    sound_path = _project_path(config.get("startup_sound", "vokrr_ui/assets/audio/startup.wav"))
    minimum_duration = float(config.get("startup_sound_duration_seconds", 5))

    if not sound_path.exists():
        LOGGER.info("Startup sound missing; generating %s", sound_path)
        generate_startup_tone(sound_path, minimum_duration)

    try:
        sound_duration = max(_duration_seconds(sound_path), 0.1)
    except (wave.Error, OSError):
        LOGGER.exception("Startup sound is invalid; regenerating %s", sound_path)
        generate_startup_tone(sound_path, minimum_duration)
        sound_duration = max(_duration_seconds(sound_path), 0.1)

    deadline = time.monotonic() + minimum_duration
    while True:
        try:
            subprocess.run(["aplay", "-q", str(sound_path)], check=True, stderr=subprocess.PIPE, text=True)
        except FileNotFoundError:
            LOGGER.warning("aplay is not installed; startup sound cannot be played")
            return
        except subprocess.CalledProcessError as exc:
            LOGGER.error("aplay failed: %s", exc.stderr.strip())
            return

        if time.monotonic() >= deadline or sound_duration >= minimum_duration:
            return
