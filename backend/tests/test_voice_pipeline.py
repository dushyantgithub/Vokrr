from __future__ import annotations

import sys
from pathlib import Path
from types import SimpleNamespace

import pytest

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from services.audio_player import PlaybackError  # noqa: E402
from services.fallback_tts_service import FallbackTTSResult  # noqa: E402
from services.nvidia_tts_service import TTSError, TTSResult  # noqa: E402
from services.voice_pipeline import VoicePipeline  # noqa: E402


class FakeHAService:
    async def entity_context(self) -> dict:
        return {"available_devices": []}


class FakeLLMService:
    configured = True

    async def decide(self, user_text: str, entity_context: dict) -> SimpleNamespace:
        return SimpleNamespace(
            raw_text='{"ha_command": false, "reply": "Hello there.", "confidence": 0.9}',
            data={
                "ha_command": False,
                "reply": "Hello there.",
                "confidence": 0.9,
            },
        )


class FakeTTSService:
    configured = True

    def __init__(self, path: Path) -> None:
        self.path = path
        self.calls: list[str] = []

    async def synthesize(self, text: str) -> TTSResult:
        self.calls.append(text)
        self.path.write_bytes(b"RIFFfake")
        return TTSResult(path=self.path, duration_ms=12.0, first_audio_ms=4.0)


class FailingTTSService:
    configured = True

    def __init__(self) -> None:
        self.calls: list[str] = []

    async def synthesize(self, text: str) -> TTSResult:
        self.calls.append(text)
        raise TTSError("tts api down")


class FakeAudioPlayer:
    def __init__(self, fail: bool = False) -> None:
        self.fail = fail
        self.calls: list[tuple[Path, bool]] = []

    def play(self, path: str | Path, non_blocking: bool = True) -> float:
        self.calls.append((Path(path), non_blocking))
        if self.fail:
            raise PlaybackError("speaker failed")
        return 33.0

    def stop(self) -> None:
        pass


class FakeFallbackTTS:
    enabled = True
    command = "espeak-ng"

    def __init__(self) -> None:
        self.calls: list[str] = []

    def speak(self, text: str) -> FallbackTTSResult:
        self.calls.append(text)
        return FallbackTTSResult(command=["espeak-ng"], duration_ms=5.0)


@pytest.mark.asyncio
async def test_voice_pipeline_uses_api_tts_and_waits_for_playback(tmp_path: Path) -> None:
    tts = FakeTTSService(tmp_path / "reply.wav")
    player = FakeAudioPlayer()
    fallback = FakeFallbackTTS()
    pipeline = VoicePipeline(
        ha_service=FakeHAService(),
        llm_service=FakeLLMService(),
        tts_service=tts,
        audio_player=player,
        fallback_tts_service=fallback,
    )

    result = await pipeline.handle_text("hello", turn_id="turn-1")

    assert tts.calls == ["Hello there."]
    assert player.calls == [(tmp_path / "reply.wav", False)]
    assert fallback.calls == []
    assert result.tts_status == "api_success"
    assert result.playback_status == "completed"
    assert result.fallback_tts_used is False
    assert result.error is None


@pytest.mark.asyncio
async def test_voice_pipeline_uses_fallback_only_after_tts_api_failure() -> None:
    tts = FailingTTSService()
    player = FakeAudioPlayer()
    fallback = FakeFallbackTTS()
    pipeline = VoicePipeline(
        ha_service=FakeHAService(),
        llm_service=FakeLLMService(),
        tts_service=tts,
        audio_player=player,
        fallback_tts_service=fallback,
    )

    result = await pipeline.handle_text("hello", turn_id="turn-2")

    assert tts.calls == ["Hello there."]
    assert player.calls == []
    assert fallback.calls == ["Hello there."]
    assert result.tts_status == "fallback_success"
    assert result.playback_status == "fallback_completed"
    assert result.fallback_tts_used is True
    assert result.error == "tts api down"


@pytest.mark.asyncio
async def test_voice_pipeline_does_not_use_tts_fallback_for_playback_failure(
    tmp_path: Path,
) -> None:
    tts = FakeTTSService(tmp_path / "reply.wav")
    player = FakeAudioPlayer(fail=True)
    fallback = FakeFallbackTTS()
    pipeline = VoicePipeline(
        ha_service=FakeHAService(),
        llm_service=FakeLLMService(),
        tts_service=tts,
        audio_player=player,
        fallback_tts_service=fallback,
    )

    result = await pipeline.handle_text("hello", turn_id="turn-3")

    assert tts.calls == ["Hello there."]
    assert player.calls == [(tmp_path / "reply.wav", False)]
    assert fallback.calls == []
    assert result.tts_status == "api_success"
    assert result.playback_status == "error"
    assert result.fallback_tts_used is False
    assert result.error == "speaker failed"
