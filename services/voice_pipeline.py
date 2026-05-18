from __future__ import annotations

import argparse
import asyncio
import json
import logging
import os
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from services.audio_player import AudioPlayer
from services.ha_service import HAExecutionResult, HAService, HomeAssistantPipelineError
from services.nvidia_llm_service import LLMError, NvidiaLLMService
from services.nvidia_tts_service import NvidiaMagpieTTSService, TTSError

logger = logging.getLogger(__name__)

LLM_FAILURE_TEXT = "I'm having trouble thinking right now."
HA_FAILURE_TEXT = "I could not control that device."


@dataclass
class PipelineResult:
    text: str
    decision: dict[str, Any] | None
    raw_llm_text: str | None
    reply: str
    ha_result: HAExecutionResult | None
    tts_output_path: str | None
    timings_ms: dict[str, float] = field(default_factory=dict)
    error: str | None = None

    def as_dict(self) -> dict[str, Any]:
        return {
            "text": self.text,
            "decision": self.decision,
            "raw_llm_text": self.raw_llm_text,
            "reply": self.reply,
            "ha_result": self.ha_result.__dict__ if self.ha_result else None,
            "tts_output_path": self.tts_output_path,
            "timings_ms": self.timings_ms,
            "error": self.error,
        }


class VoicePipeline:
    def __init__(
        self,
        ha_service: HAService | None = None,
        llm_service: NvidiaLLMService | None = None,
        tts_service: NvidiaMagpieTTSService | None = None,
        audio_player: AudioPlayer | None = None,
    ) -> None:
        self.ha_service = ha_service or HAService()
        self.llm_service = llm_service or NvidiaLLMService()
        self.tts_service = tts_service or NvidiaMagpieTTSService()
        self.audio_player = audio_player or AudioPlayer()

    def stop_speech(self) -> None:
        self.audio_player.stop()

    async def handle_text(
        self,
        text: str,
        stt_duration_ms: float | None = None,
        speak: bool = True,
    ) -> PipelineResult:
        started = time.perf_counter()
        timings: dict[str, float] = {}
        if stt_duration_ms is not None:
            timings["stt"] = stt_duration_ms

        text = text.strip()
        decision: dict[str, Any] | None = None
        raw_llm_text: str | None = None
        ha_result: HAExecutionResult | None = None
        reply = ""
        error: str | None = None

        try:
            entity_started = time.perf_counter()
            entity_context = await self.ha_service.entity_context()
            timings["ha_entities"] = elapsed_ms(entity_started)

            llm_started = time.perf_counter()
            llm_decision = await self.llm_service.decide(text, entity_context)
            timings["llm"] = elapsed_ms(llm_started)
            raw_llm_text = llm_decision.raw_text
            decision = normalize_decision(llm_decision.data)

            if should_clarify(decision):
                reply = decision.get("clarification_question") or decision.get("reply") or "Which device do you mean?"
            elif decision.get("ha_command"):
                ha_started = time.perf_counter()
                ha_result = await self._handle_ha(decision)
                timings["ha"] = elapsed_ms(ha_started)
                reply = ha_result.message if ha_result.ok else HA_FAILURE_TEXT
            else:
                reply = short_text(decision.get("reply") or "I'm here.")
        except LLMError as exc:
            logger.exception("LLM stage failed")
            error = str(exc)
            reply = LLM_FAILURE_TEXT
        except Exception as exc:
            logger.exception("Voice pipeline failed")
            error = str(exc)
            reply = "Something went wrong."

        tts_path: str | None = None
        if speak and reply:
            try:
                tts_started = time.perf_counter()
                tts_result = await self.tts_service.synthesize(reply)
                timings["tts"] = tts_result.duration_ms
                if tts_result.first_audio_ms is not None:
                    timings["tts_first_audio"] = tts_result.first_audio_ms
                playback_started = time.perf_counter()
                self.audio_player.play(tts_result.path, non_blocking=True)
                timings["playback_start_delay"] = elapsed_ms(playback_started)
                timings["tts_stage_total"] = elapsed_ms(tts_started)
                tts_path = str(tts_result.path)
            except TTSError as exc:
                logger.exception("TTS failed")
                error = error or str(exc)
                print(reply)
            except Exception as exc:
                logger.exception("Playback failed")
                error = error or str(exc)
                print(reply)

        timings["total_roundtrip"] = elapsed_ms(started)
        logger.info("voice.pipeline timings=%s reply=%r", timings, reply)
        return PipelineResult(
            text=text,
            decision=decision,
            raw_llm_text=raw_llm_text,
            reply=reply,
            ha_result=ha_result,
            tts_output_path=tts_path,
            timings_ms=timings,
            error=error,
        )

    async def _handle_ha(self, decision: dict[str, Any]) -> HAExecutionResult:
        try:
            if decision.get("intent") == "query_device_state" or decision.get("action") == "get_state":
                return await self.ha_service.query_state(decision)
            result = await self.ha_service.execute(decision)
            if not result.ok:
                return result
            return result
        except HomeAssistantPipelineError:
            logger.exception("Home Assistant command failed")
            return HAExecutionResult(ok=False, message=HA_FAILURE_TEXT)
        except Exception:
            logger.exception("Unexpected Home Assistant command failure")
            return HAExecutionResult(ok=False, message=HA_FAILURE_TEXT)


def normalize_decision(decision: dict[str, Any]) -> dict[str, Any]:
    normalized = dict(decision)
    normalized["ha_command"] = bool(normalized.get("ha_command"))
    normalized["needs_confirmation"] = bool(normalized.get("needs_confirmation"))
    normalized["needs_clarification"] = bool(normalized.get("needs_clarification"))
    try:
        normalized["confidence"] = float(normalized.get("confidence", 0))
    except (TypeError, ValueError):
        normalized["confidence"] = 0.0
    return normalized


def should_clarify(decision: dict[str, Any]) -> bool:
    if is_collective_room_command(decision):
        return False
    if decision.get("needs_confirmation") or decision.get("needs_clarification"):
        return True
    if decision.get("ha_command") and float(decision.get("confidence", 0)) < 0.65:
        return True
    return False


def is_collective_room_command(decision: dict[str, Any]) -> bool:
    if not decision.get("ha_command") or not decision.get("room"):
        return False
    name = " ".join(str(decision.get("device_name") or "").lower().replace("_", " ").split())
    return name in {"light", "lights", "room lights", "all lights"}


def short_text(text: str, limit: int = 240) -> str:
    text = " ".join(str(text).split())
    return text if len(text) <= limit else text[: limit - 1].rstrip() + "."


def elapsed_ms(started: float) -> float:
    return round((time.perf_counter() - started) * 1000, 2)


def load_dotenv(path: str | Path = ".env") -> None:
    env_path = Path(path)
    if not env_path.exists():
        return
    for line in env_path.read_text().splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in stripped:
            continue
        key, value = stripped.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


async def run_cli(text: str, no_speak: bool = False) -> int:
    load_dotenv()
    logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"), format="%(asctime)s %(levelname)s %(name)s %(message)s")
    result = await VoicePipeline().handle_text(text, speak=not no_speak)
    print(json.dumps(result.as_dict(), indent=2, ensure_ascii=False))
    return 0 if result.error is None else 1


def main() -> None:
    parser = argparse.ArgumentParser(description="Run the Vokrr realtime voice pipeline from text.")
    parser.add_argument("--text", required=True, help="Text to process as if Whisper transcribed it.")
    parser.add_argument("--no-speak", action="store_true", help="Skip TTS and audio playback.")
    args = parser.parse_args()
    raise SystemExit(asyncio.run(run_cli(args.text, no_speak=args.no_speak)))


if __name__ == "__main__":
    main()
