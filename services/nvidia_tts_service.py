from __future__ import annotations

import asyncio
import logging
import os
import tempfile
import time
import wave
from dataclasses import dataclass
from pathlib import Path

logger = logging.getLogger(__name__)


class TTSError(RuntimeError):
    pass


@dataclass(frozen=True)
class TTSResult:
    path: Path
    duration_ms: float
    first_audio_ms: float | None


class NvidiaMagpieTTSService:
    def __init__(
        self,
        api_key: str | None = None,
        server: str | None = None,
        function_id: str | None = None,
        voice: str | None = None,
        language_code: str | None = None,
        sample_rate_hz: int | None = None,
    ) -> None:
        self.api_key = (
            api_key
            or os.getenv("NVIDIA_API_KEY")
            or os.getenv("NVIDIA_BUILD_API_KEY")
            or os.getenv("MAGPIE_API_KEY", "")
        )
        self.server = server or os.getenv("NVIDIA_TTS_GRPC_SERVER", "grpc.nvcf.nvidia.com:443")
        self.function_id = function_id or os.getenv(
            "NVIDIA_TTS_FUNCTION_ID",
            "877104f7-e885-42b9-8de8-f6e4c6303969",
        )
        self.voice = voice or os.getenv(
            "NVIDIA_TTS_DEFAULT_VOICE",
            "Magpie-Multilingual.EN-US.Aria",
        )
        self.language_code = language_code or os.getenv("NVIDIA_TTS_LANGUAGE_CODE", "en-US")
        self.sample_rate_hz = sample_rate_hz or int(os.getenv("NVIDIA_TTS_SAMPLE_RATE_HZ", "44100"))

    @property
    def configured(self) -> bool:
        return bool(self.api_key)

    async def synthesize(self, text: str) -> TTSResult:
        if not self.api_key:
            raise TTSError("NVIDIA_API_KEY or NVIDIA_BUILD_API_KEY is required")
        return await asyncio.to_thread(self._synthesize_sync, text)

    def _synthesize_sync(self, text: str) -> TTSResult:
        try:
            import riva.client
            from riva.client.proto.riva_audio_pb2 import AudioEncoding
        except Exception as exc:
            raise TTSError("nvidia-riva-client is required for Magpie TTS") from exc

        started = time.perf_counter()
        first_audio_ms: float | None = None
        fd, output_name = tempfile.mkstemp(prefix="vokrr-tts-", suffix=".wav")
        os.close(fd)
        output_path = Path(output_name)

        auth = riva.client.Auth(
            use_ssl=True,
            uri=self.server,
            metadata_args=[
                ("function-id", self.function_id),
                ("authorization", f"Bearer {self.api_key}"),
            ],
        )
        service = riva.client.SpeechSynthesisService(auth)

        try:
            audio_bytes = 0
            with wave.open(str(output_path), "wb") as wav_file:
                wav_file.setnchannels(1)
                wav_file.setsampwidth(2)
                wav_file.setframerate(self.sample_rate_hz)
                responses = service.synthesize_online(
                    [text],
                    self.voice,
                    self.language_code,
                    sample_rate_hz=self.sample_rate_hz,
                    encoding=AudioEncoding.LINEAR_PCM,
                )
                for response in responses:
                    chunk = bytes(response.audio or b"")
                    if not chunk:
                        continue
                    if first_audio_ms is None:
                        first_audio_ms = (time.perf_counter() - started) * 1000
                    audio_bytes += len(chunk)
                    wav_file.writeframesraw(chunk)
                if audio_bytes <= 0:
                    raise TTSError("NVIDIA Magpie TTS returned no audio")
        except Exception:
            output_path.unlink(missing_ok=True)
            raise

        return TTSResult(
            path=output_path,
            duration_ms=(time.perf_counter() - started) * 1000,
            first_audio_ms=first_audio_ms,
        )
