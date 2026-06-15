from __future__ import annotations

import logging
import os
import shutil
import subprocess
import threading
import time
from pathlib import Path

logger = logging.getLogger(__name__)


class PlaybackError(RuntimeError):
    pass


class AudioPlayer:
    def __init__(self, output_device: str | None = None, keep_audio: bool | None = None) -> None:
        self.output_device = output_device or os.getenv("VOICE_OUTPUT_DEVICE") or None
        self.keep_audio = (
            keep_audio
            if keep_audio is not None
            else os.getenv("VOICE_KEEP_TTS_FILES", "0") == "1"
        )
        self._lock = threading.Lock()
        self._process: subprocess.Popen[bytes] | None = None

    def play(self, path: str | Path, non_blocking: bool = True) -> float:
        audio_path = Path(path)
        if not audio_path.exists():
            raise PlaybackError(f"Audio file does not exist: {audio_path}")
        if audio_path.stat().st_size <= 0:
            raise PlaybackError(f"Audio file is empty: {audio_path}")

        started = time.perf_counter()
        with self._lock:
            self.stop()
            command = self._command(audio_path)
            env = os.environ.copy()
            if self.output_device:
                env["AUDIODEV"] = self.output_device
            try:
                self._process = subprocess.Popen(
                    command,
                    env=env,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
            except Exception as exc:
                raise PlaybackError(f"Could not start audio player: {exc}") from exc
            process = self._process

        if non_blocking:
            threading.Thread(
                target=self._wait_and_cleanup,
                args=(process, audio_path, started, False),
                daemon=True,
            ).start()
            return 0.0
        return self._wait_and_cleanup(process, audio_path, started, True)

    def stop(self) -> None:
        process = self._process
        if process and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=0.8)
            except subprocess.TimeoutExpired:
                process.kill()
        self._process = None

    def _command(self, path: Path) -> list[str]:
        if shutil.which("aplay"):
            command = ["aplay", "-q"]
            if self.output_device:
                command.extend(["-D", self.output_device])
            command.append(str(path))
            return command
        if shutil.which("ffplay"):
            return ["ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet", str(path)]
        raise PlaybackError("No audio player found. Install aplay or ffplay.")

    def _wait_and_cleanup(
        self,
        process: subprocess.Popen[bytes],
        path: Path,
        started: float,
        raise_on_error: bool,
    ) -> float:
        returncode = 0
        try:
            returncode = process.wait()
        finally:
            duration_ms = round((time.perf_counter() - started) * 1000, 2)
            with self._lock:
                if self._process is process:
                    self._process = None
            if not self.keep_audio:
                try:
                    path.unlink(missing_ok=True)
                except Exception as exc:
                    logger.debug("Could not remove TTS temp file %s: %s", path, exc)
        if returncode != 0:
            message = f"Audio playback failed with exit code {returncode}"
            if raise_on_error:
                raise PlaybackError(message)
            logger.warning(message)
        return duration_ms
