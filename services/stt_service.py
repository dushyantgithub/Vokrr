from __future__ import annotations

import time
from collections.abc import Callable
from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class STTResult:
    text: str
    duration_ms: float


class ExistingWhisperSTTService:
    """Adapter for the existing Raspberry Pi Whisper implementation.

    The listener owns microphone capture and Whisper model lifecycle. This
    adapter exists so the new pipeline has a clean STT service boundary without
    moving or rewriting that already-working code.
    """

    def __init__(self, transcribe: Callable[..., str]) -> None:
        self._transcribe = transcribe

    def transcribe(self, *args: Any, **kwargs: Any) -> STTResult:
        started = time.perf_counter()
        text = self._transcribe(*args, **kwargs)
        return STTResult(text=text, duration_ms=(time.perf_counter() - started) * 1000)
