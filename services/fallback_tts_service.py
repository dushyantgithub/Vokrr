from __future__ import annotations

import logging
import os
import shlex
import shutil
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path

logger = logging.getLogger(__name__)


class FallbackTTSError(RuntimeError):
    pass


@dataclass(frozen=True)
class FallbackTTSResult:
    command: list[str]
    duration_ms: float


class CommandFallbackTTSService:
    def __init__(
        self,
        enabled: bool | None = None,
        command: str | None = None,
        rate: str | None = None,
        output_device: str | None = None,
        timeout_seconds: float | None = None,
    ) -> None:
        self.enabled = (
            enabled
            if enabled is not None
            else os.getenv("VOICE_TTS_FALLBACK_ENABLED", "1") == "1"
        )
        self.command = command or os.getenv("VOICE_TTS_COMMAND", "espeak-ng")
        self.rate = rate or os.getenv("VOICE_TTS_RATE", "150")
        self.output_device = output_device or os.getenv("VOICE_OUTPUT_DEVICE") or None
        self.timeout_seconds = timeout_seconds or float(
            os.getenv("VOICE_TTS_FALLBACK_TIMEOUT_SECONDS", "8")
        )

    @property
    def configured(self) -> bool:
        return self.enabled and bool(self.command.strip())

    def speak(self, text: str) -> FallbackTTSResult:
        text = " ".join(str(text).split())
        if not text:
            raise FallbackTTSError("Fallback TTS received empty text")
        if not self.enabled:
            raise FallbackTTSError("Fallback TTS is disabled")

        command = shlex.split(self.command)
        if not command:
            raise FallbackTTSError("Fallback TTS command is empty")

        executable = command[0]
        if shutil.which(executable) is None and not Path(executable).exists():
            raise FallbackTTSError(f"Fallback TTS command not found: {executable}")

        command = [*command, "-s", self.rate, text]
        env = os.environ.copy()
        if self.output_device:
            env["AUDIODEV"] = self.output_device

        started = time.perf_counter()
        try:
            result = subprocess.run(
                command,
                env=env,
                check=False,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=self.timeout_seconds,
            )
        except Exception as exc:
            raise FallbackTTSError(f"Fallback TTS failed to run: {exc}") from exc

        duration_ms = round((time.perf_counter() - started) * 1000, 2)
        if result.returncode != 0:
            raise FallbackTTSError(f"Fallback TTS exited with code {result.returncode}")

        logger.info("voice.tts_fallback command=%s duration_ms=%s", command[0], duration_ms)
        return FallbackTTSResult(command=command, duration_ms=duration_ms)
