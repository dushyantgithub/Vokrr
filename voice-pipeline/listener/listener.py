import logging
import os
import queue
import random
import subprocess
import threading
import time
import asyncio
import json
import uuid
from collections import deque
from pathlib import Path
from typing import Any

import httpx
import numpy as np
from fastapi import FastAPI

from services.voice_pipeline import VoicePipeline

BACKEND_URL = os.getenv("VOICE_BACKEND_URL", "http://localhost:8080").rstrip("/")
APP_USERNAME = os.getenv("APP_BOOTSTRAP_ADMIN_USERNAME") or os.getenv("APP_USERNAME", "admin")
APP_PASSWORD = os.getenv("APP_BOOTSTRAP_ADMIN_PASSWORD") or os.getenv("APP_PASSWORD", "")
WAKE_WORD_DISPLAY = os.getenv("VOICE_WAKE_WORD", "Jarvis")
PORCUPINE_ACCESS_KEY = os.getenv("PORCUPINE_API_KEY") or os.getenv("PORCUPINE_ACCESS_KEY", "")
PORCUPINE_KEYWORD_PATH = Path(
    os.getenv("PORCUPINE_KEYWORD_PATH", "/wake-word/Jarvis_en_raspberry-pi_v4_0_0.ppn")
)
PORCUPINE_SENSITIVITY = float(os.getenv("PORCUPINE_SENSITIVITY", "0.35"))
LISTENER_ENABLED = os.getenv("VOICE_LISTENER_ENABLED", "1") == "1"
INPUT_DEVICE = os.getenv("VOICE_INPUT_DEVICE") or None
OUTPUT_DEVICE = os.getenv("VOICE_OUTPUT_DEVICE") or None
COMMAND_RECORD_SECONDS = float(os.getenv("VOICE_COMMAND_RECORD_SECONDS", "10"))
COMMAND_MIN_SECONDS = float(os.getenv("VOICE_COMMAND_MIN_SECONDS", "1.2"))
COMMAND_SILENCE_SECONDS = float(os.getenv("VOICE_COMMAND_SILENCE_SECONDS", "1.1"))
COMMAND_SILENCE_RMS = int(os.getenv("VOICE_COMMAND_SILENCE_RMS", "450"))
WAKE_COOLDOWN_SECONDS = float(os.getenv("VOICE_WAKE_COOLDOWN_SECONDS", "2.5"))
POST_SPEECH_COOLDOWN_SECONDS = float(os.getenv("VOICE_POST_SPEECH_COOLDOWN_SECONDS", "0.8"))
WAKE_MIN_RMS = float(os.getenv("VOICE_WAKE_MIN_RMS", "350"))
WAKE_MIN_PEAK_RMS = float(os.getenv("VOICE_WAKE_MIN_PEAK_RMS", "650"))
WAKE_RMS_WINDOW_FRAMES = int(os.getenv("VOICE_WAKE_RMS_WINDOW_FRAMES", "8"))
AUDIO_QUEUE_MAX_CHUNKS = int(os.getenv("VOICE_AUDIO_QUEUE_MAX_CHUNKS", "64"))
AUDIO_FRAME_TIMEOUT_SECONDS = float(os.getenv("VOICE_AUDIO_FRAME_TIMEOUT_SECONDS", "5"))
VOICE_FEEDBACK_ENABLED = os.getenv("VOICE_FEEDBACK_ENABLED", "1") == "1"
VOICE_FEEDBACK_WAKE_TEXT = os.getenv("VOICE_FEEDBACK_WAKE_TEXT", "How can I help you sir?")
VOICE_FEEDBACK_MISUNDERSTOOD_TEXT = os.getenv(
    "VOICE_FEEDBACK_MISUNDERSTOOD_TEXT",
    "I am afraid sir, but I didnt get you",
)
VOICE_TTS_COMMAND = os.getenv("VOICE_TTS_COMMAND", "espeak-ng")
VOICE_TTS_RATE = os.getenv("VOICE_TTS_RATE", "150")
VOICE_NVIDIA_PIPELINE_ENABLED = os.getenv("VOICE_NVIDIA_PIPELINE_ENABLED", "1") == "1"
WHISPER_MODEL_NAME = os.getenv("WHISPER_MODEL", "base.en")
WHISPER_LANGUAGE = os.getenv("WHISPER_LANGUAGE", "en")
WHISPER_DEVICE = os.getenv("WHISPER_DEVICE", "cpu")
WHISPER_COMPUTE_TYPE = os.getenv("WHISPER_COMPUTE_TYPE", "int8")
ASSIST_PROMPTS = [
    VOICE_FEEDBACK_WAKE_TEXT,
]

app = FastAPI(title="Vokrr Voice Listener", version="0.1.0")
logger = logging.getLogger(__name__)

audio_queue: queue.Queue[bytes] = queue.Queue(maxsize=max(1, AUDIO_QUEUE_MAX_CHUNKS))
capture_enabled = threading.Event()
status = {
    "ok": False,
    "state": "starting",
    "message": "Voice listener starting",
    "wake_word": WAKE_WORD_DISPLAY,
    "wake_engine": "porcupine",
    "stt_engine": "faster-whisper",
    "keyword_path": str(PORCUPINE_KEYWORD_PATH),
    "porcupine_sensitivity": PORCUPINE_SENSITIVITY,
    "whisper_model": WHISPER_MODEL_NAME,
}
token_cache = {"token": None, "time": 0.0}
whisper_cache = {"model": None}
pipeline_cache = {"pipeline": None}


@app.on_event("startup")
def startup() -> None:
    if LISTENER_ENABLED:
        thread = threading.Thread(target=run_listener, daemon=True)
        thread.start()
    else:
        status.update(ok=True, state="disabled", message="Voice listener disabled")


@app.get("/health")
async def health() -> dict:
    return status


def run_listener() -> None:
    try:
        import pvporcupine
        import sounddevice as sd
    except Exception as exc:
        status.update(ok=False, state="dependency_error", message=str(exc))
        return

    if not PORCUPINE_ACCESS_KEY:
        status.update(
            ok=False,
            state="porcupine_config_error",
            message="PORCUPINE_API_KEY is required for wake-word detection.",
        )
        return

    if not PORCUPINE_KEYWORD_PATH.exists():
        status.update(
            ok=False,
            state="wake_word_missing",
            message=f"Porcupine wake-word file missing at {PORCUPINE_KEYWORD_PATH}.",
        )
        return

    porcupine = None
    try:
        porcupine = pvporcupine.create(
            access_key=PORCUPINE_ACCESS_KEY,
            keyword_paths=[str(PORCUPINE_KEYWORD_PATH)],
            sensitivities=[clamp_float(PORCUPINE_SENSITIVITY, 0.0, 1.0)],
        )
        sample_rate = porcupine.sample_rate
        frame_length = porcupine.frame_length
        input_sample_rate = select_input_sample_rate(sd, sample_rate)
        input_blocksize = max(1, round(frame_length * input_sample_rate / sample_rate))
        load_whisper_model()
    except Exception as exc:
        status.update(ok=False, state="startup_error", message=str(exc))
        return

    def callback(indata, frames, time_info, error) -> None:
        if error and "overflow" not in str(error).lower():
            status.update(ok=False, state="audio_error", message=str(error))
            log_voice_turn(None, "mic_callback_error", error=str(error))
        if not capture_enabled.is_set():
            return
        try:
            audio_queue.put_nowait(bytes(indata))
        except queue.Full:
            try:
                audio_queue.get_nowait()
                status["dropped_audio_chunks"] = int(status.get("dropped_audio_chunks", 0)) + 1
            except queue.Empty:
                pass
            try:
                audio_queue.put_nowait(bytes(indata))
            except queue.Full:
                status["dropped_audio_chunks"] = int(status.get("dropped_audio_chunks", 0)) + 1

    status.update(
        ok=True,
        state="idle",
        message="waiting for wake-word",
        sample_rate=sample_rate,
        input_sample_rate=input_sample_rate,
        frame_length=frame_length,
        input_device=INPUT_DEVICE or "default",
    )

    pending_audio = np.array([], dtype=np.int16)
    recent_wake_rms: deque[float] = deque(maxlen=max(1, WAKE_RMS_WINDOW_FRAMES))
    last_wake_monotonic = 0.0

    def clear_audio_buffers() -> int:
        nonlocal pending_audio
        dropped = drain_audio_queue()
        pending_audio = np.array([], dtype=np.int16)
        recent_wake_rms.clear()
        return dropped

    def pause_capture(turn_id: str | None, event: str) -> None:
        capture_enabled.clear()
        dropped = clear_audio_buffers()
        log_voice_turn(turn_id, event, capture="paused", dropped_audio_chunks=dropped)

    def resume_capture(turn_id: str | None, event: str) -> None:
        dropped = clear_audio_buffers()
        capture_enabled.set()
        log_voice_turn(turn_id, event, capture="enabled", dropped_audio_chunks=dropped)

    def finish_turn(turn_id: str) -> None:
        pause_capture(turn_id, "turn_finishing")
        if POST_SPEECH_COOLDOWN_SECONDS > 0:
            time.sleep(POST_SPEECH_COOLDOWN_SECONDS)
        reset_to_idle(turn_id=turn_id)
        resume_capture(turn_id, "idle_capture_resumed")

    def handle_wake_turn(turn_id: str) -> None:
        prompt = random.choice(ASSIST_PROMPTS)
        status.update(
            ok=True,
            state="wake_detected",
            message=f"{WAKE_WORD_DISPLAY} detected",
            current_turn_id=turn_id,
            last_wake=time.time(),
            last_text="",
            last_pipeline=None,
            last_stt_duration_ms=None,
        )
        post_voice_event("wake_detected", status["message"])
        log_voice_turn(turn_id, "wake_detected", wake_word=WAKE_WORD_DISPLAY)

        pause_capture(turn_id, "wake_capture_paused")
        stop_pipeline_speech(turn_id)
        status.update(ok=True, state="speaking", message=prompt)
        post_voice_event("speaking", prompt)
        speak(prompt, turn_id=turn_id, reason="wake_prompt")

        if POST_SPEECH_COOLDOWN_SECONDS > 0:
            time.sleep(POST_SPEECH_COOLDOWN_SECONDS)
        resume_capture(turn_id, "recording_capture_resumed")
        try:
            command_audio = record_command(next_porcupine_frame, sample_rate, turn_id)
        finally:
            pause_capture(turn_id, "recording_capture_paused")

        text = transcribe_audio(command_audio, sample_rate, turn_id)
        status.update(last_text=text)

        if text:
            submit_command(text, turn_id)
        else:
            status.update(ok=True, state="speaking", message=VOICE_FEEDBACK_MISUNDERSTOOD_TEXT)
            log_voice_turn(turn_id, "empty_stt_result")
            post_voice_event("speaking", VOICE_FEEDBACK_MISUNDERSTOOD_TEXT)
            speak(VOICE_FEEDBACK_MISUNDERSTOOD_TEXT, turn_id=turn_id, reason="empty_stt")
            post_voice_event("error", VOICE_FEEDBACK_MISUNDERSTOOD_TEXT)

    def next_porcupine_frame() -> np.ndarray:
        nonlocal pending_audio
        while len(pending_audio) < frame_length:
            try:
                data = audio_queue.get(timeout=AUDIO_FRAME_TIMEOUT_SECONDS)
            except queue.Empty:
                raise RuntimeError("Timed out waiting for microphone audio") from None
            chunk = resample_pcm(pcm_from_bytes(data), input_sample_rate, sample_rate)
            pending_audio = np.concatenate([pending_audio, chunk])
        frame = pending_audio[:frame_length]
        pending_audio = pending_audio[frame_length:]
        return frame

    try:
        with sd.RawInputStream(
            samplerate=input_sample_rate,
            blocksize=input_blocksize,
            dtype="int16",
            channels=1,
            device=INPUT_DEVICE,
            callback=callback,
        ):
            post_voice_event("idle", status["message"])
            resume_capture(None, "listener_ready")
            while True:
                pcm = next_porcupine_frame()
                frame_rms = rms(pcm)
                recent_wake_rms.append(frame_rms)

                try:
                    result = porcupine.process(pcm)
                except Exception as exc:
                    status.update(ok=False, state="wake_engine_error", message=str(exc))
                    log_voice_turn(None, "wake_engine_error", error=str(exc))
                    post_voice_event("error", "Wake-word engine failed")
                    raise
                if result < 0:
                    continue

                now = time.monotonic()
                recent_avg_rms = float(np.mean(recent_wake_rms)) if recent_wake_rms else frame_rms
                recent_peak_rms = max(recent_wake_rms) if recent_wake_rms else frame_rms
                cooldown_remaining = WAKE_COOLDOWN_SECONDS - (now - last_wake_monotonic)
                if cooldown_remaining > 0:
                    log_voice_turn(
                        None,
                        "wake_rejected_cooldown",
                        cooldown_remaining=round(cooldown_remaining, 2),
                        frame_rms=round(frame_rms, 2),
                    )
                    clear_audio_buffers()
                    continue
                if recent_avg_rms < WAKE_MIN_RMS or recent_peak_rms < WAKE_MIN_PEAK_RMS:
                    log_voice_turn(
                        None,
                        "wake_rejected_low_energy",
                        frame_rms=round(frame_rms, 2),
                        recent_avg_rms=round(recent_avg_rms, 2),
                        recent_peak_rms=round(recent_peak_rms, 2),
                        min_rms=WAKE_MIN_RMS,
                        min_peak_rms=WAKE_MIN_PEAK_RMS,
                    )
                    clear_audio_buffers()
                    continue

                turn_id = new_turn_id()
                last_wake_monotonic = now
                log_voice_turn(
                    turn_id,
                    "wake_accepted",
                    porcupine_result=result,
                    frame_rms=round(frame_rms, 2),
                    recent_avg_rms=round(recent_avg_rms, 2),
                    recent_peak_rms=round(recent_peak_rms, 2),
                    sensitivity=clamp_float(PORCUPINE_SENSITIVITY, 0.0, 1.0),
                )
                try:
                    handle_wake_turn(turn_id)
                except Exception as exc:
                    logger.exception("Voice turn failed")
                    status.update(ok=False, state="turn_error", message=str(exc))
                    log_voice_turn(turn_id, "turn_error", error=str(exc))
                    post_voice_event("error", "Voice turn failed")
                    pause_capture(turn_id, "turn_error_capture_paused")
                    speak(VOICE_FEEDBACK_MISUNDERSTOOD_TEXT, turn_id=turn_id, reason="turn_error")
                finally:
                    last_wake_monotonic = time.monotonic()
                    finish_turn(turn_id)
    except Exception as exc:
        status.update(ok=False, state="listener_error", message=str(exc))
        log_voice_turn(None, "listener_error", error=str(exc))
        post_voice_event("error", status["message"])
    finally:
        if porcupine is not None:
            porcupine.delete()


def select_input_sample_rate(sd, target_sample_rate: int) -> int:
    candidate_rates = []
    for rate in [target_sample_rate, 48000, 44100, 32000, 16000, 8000]:
        if rate not in candidate_rates:
            candidate_rates.append(rate)

    errors = []
    for rate in candidate_rates:
        try:
            sd.check_input_settings(
                device=INPUT_DEVICE,
                samplerate=rate,
                channels=1,
                dtype="int16",
            )
            return rate
        except Exception as exc:
            errors.append(f"{rate}: {exc}")

    raise RuntimeError("No supported microphone sample rate found. " + "; ".join(errors))


def resample_pcm(pcm: np.ndarray, source_rate: int, target_rate: int) -> np.ndarray:
    if source_rate == target_rate or pcm.size == 0:
        return pcm

    source_positions = np.arange(pcm.size, dtype=np.float32)
    target_length = max(1, round(pcm.size * target_rate / source_rate))
    target_positions = np.linspace(0, pcm.size - 1, target_length, dtype=np.float32)
    resampled = np.interp(target_positions, source_positions, pcm.astype(np.float32))
    return np.clip(resampled, -32768, 32767).astype(np.int16)


def record_command(next_frame, sample_rate: int, turn_id: str | None = None) -> np.ndarray:
    frames: list[np.ndarray] = []
    started_at = time.time()
    last_voice_at = started_at
    peak_rms = 0.0
    stop_reason = "timeout"

    status.update(ok=True, state="recording", message="waiting for command")
    post_voice_event("recording", "waiting for command")
    log_voice_turn(
        turn_id,
        "recording_start",
        sample_rate=sample_rate,
        max_seconds=COMMAND_RECORD_SECONDS,
        silence_rms=COMMAND_SILENCE_RMS,
    )

    while time.time() - started_at < COMMAND_RECORD_SECONDS:
        pcm = next_frame()

        frames.append(pcm.copy())
        frame_rms = rms(pcm)
        peak_rms = max(peak_rms, frame_rms)
        now = time.time()
        if frame_rms >= COMMAND_SILENCE_RMS:
            last_voice_at = now
        if (
            now - started_at >= COMMAND_MIN_SECONDS
            and now - last_voice_at >= COMMAND_SILENCE_SECONDS
        ):
            stop_reason = "silence"
            break

    if not frames:
        log_voice_turn(turn_id, "recording_stop", duration_ms=0, frames=0, stop_reason="empty")
        return np.array([], dtype=np.int16)
    audio = np.concatenate(frames)
    log_voice_turn(
        turn_id,
        "recording_stop",
        duration_ms=round((time.time() - started_at) * 1000, 2),
        frames=len(frames),
        samples=int(audio.size),
        peak_rms=round(peak_rms, 2),
        stop_reason=stop_reason,
    )
    return audio


def transcribe_audio(audio: np.ndarray, sample_rate: int, turn_id: str | None = None) -> str:
    if audio.size == 0:
        log_voice_turn(turn_id, "stt_skipped_empty_audio")
        return ""

    status.update(ok=True, state="transcribing", message="Transcribing...")
    post_voice_event("processing", "Transcribing...")
    log_voice_turn(turn_id, "stt_start", samples=int(audio.size), sample_rate=sample_rate)
    started = time.perf_counter()
    model = load_whisper_model()
    audio_float = audio.astype(np.float32) / 32768.0
    try:
        segments, _info = model.transcribe(
            audio_float,
            language=WHISPER_LANGUAGE,
            vad_filter=True,
        )
        text = " ".join(segment.text.strip() for segment in segments).strip()
    except Exception as exc:
        status.update(ok=False, state="stt_error", message=str(exc))
        log_voice_turn(turn_id, "stt_error", error=str(exc))
        raise
    duration_ms = round((time.perf_counter() - started) * 1000, 2)
    status.update(last_stt_duration_ms=duration_ms)
    log_voice_turn(turn_id, "stt_done", duration_ms=duration_ms, text=text)
    return text.lower()


def load_whisper_model():
    if whisper_cache["model"] is None:
        status.update(
            ok=True,
            state="loading_stt",
            message=f"Loading Whisper {WHISPER_MODEL_NAME}...",
        )
        from faster_whisper import WhisperModel

        whisper_cache["model"] = WhisperModel(
            WHISPER_MODEL_NAME,
            device=WHISPER_DEVICE,
            compute_type=WHISPER_COMPUTE_TYPE,
        )
    return whisper_cache["model"]


def pcm_from_bytes(data: bytes) -> np.ndarray:
    return np.frombuffer(data, dtype=np.int16)


def rms(pcm: np.ndarray) -> float:
    if pcm.size == 0:
        return 0.0
    return float(np.sqrt(np.mean(np.square(pcm.astype(np.float32)))))


def clamp_float(value: float, minimum: float, maximum: float) -> float:
    return max(minimum, min(maximum, value))


def new_turn_id() -> str:
    return f"voice-{uuid.uuid4().hex[:12]}"


def log_voice_turn(turn_id: str | None, event: str, **fields: Any) -> None:
    payload = {
        "event": event,
        "turn_id": turn_id,
        **{key: value for key, value in fields.items() if value is not None},
    }
    logger.info(
        "voice.turn %s",
        json.dumps(payload, ensure_ascii=False, sort_keys=True, default=str),
    )


def submit_command(text: str, turn_id: str | None = None) -> None:
    status.update(ok=True, state="processing", message=f"Heard: {text}")
    post_voice_event("processing", status["message"])
    log_voice_turn(
        turn_id,
        "command_submit",
        text=text,
        nvidia_pipeline=VOICE_NVIDIA_PIPELINE_ENABLED,
    )
    if VOICE_NVIDIA_PIPELINE_ENABLED:
        try:
            pipeline = get_voice_pipeline()
            result = asyncio.run(
                pipeline.handle_text(
                    text,
                    stt_duration_ms=status.get("last_stt_duration_ms"),
                    speak=VOICE_FEEDBACK_ENABLED,
                    turn_id=turn_id,
                    wait_for_playback=True,
                )
            )
            status.update(
                ok=result.error is None,
                state="done" if result.error is None else "error",
                message=result.reply,
                last_pipeline=result.as_dict(),
            )
            log_voice_turn(
                turn_id,
                "command_pipeline_done",
                error=result.error,
                tts_status=result.tts_status,
                playback_status=result.playback_status,
                fallback_tts_used=result.fallback_tts_used,
            )
            post_voice_event("done" if result.error is None else "error", result.reply)
            return
        except Exception as exc:
            logger.exception("NVIDIA voice pipeline crashed")
            status.update(ok=False, state="pipeline_error", message=str(exc))
            log_voice_turn(turn_id, "command_pipeline_crash", error=str(exc))
            post_voice_event("error", "Voice command failed")
            speak(VOICE_FEEDBACK_MISUNDERSTOOD_TEXT, turn_id=turn_id, reason="pipeline_crash")
            return

    try:
        log_voice_turn(turn_id, "legacy_backend_start")
        token = get_token()
        with httpx.Client(timeout=20) as client:
            response = client.post(
                f"{BACKEND_URL}/api/voice/command",
                headers={"Authorization": f"Bearer {token}"},
                json={"text": text},
            )
        if response.status_code >= 400:
            status.update(ok=False, state="command_error", message=response.text)
            log_voice_turn(
                turn_id,
                "legacy_backend_error",
                status_code=response.status_code,
                body=response.text[:240],
            )
            speak(VOICE_FEEDBACK_MISUNDERSTOOD_TEXT, turn_id=turn_id, reason="legacy_backend_error")
            post_voice_event("error", "Voice command failed")
            return
        payload = response.json()
        message = payload.get("message", "Done")
        if not payload.get("understood", False):
            speak(
                VOICE_FEEDBACK_MISUNDERSTOOD_TEXT,
                turn_id=turn_id,
                reason="legacy_not_understood",
            )
        status.update(ok=True, state="done", message=message)
        log_voice_turn(
            turn_id,
            "legacy_backend_done",
            understood=payload.get("understood", False),
            message=message,
        )
        post_voice_event("done", message)
    except Exception as exc:
        status.update(ok=False, state="command_error", message=str(exc))
        log_voice_turn(turn_id, "legacy_backend_exception", error=str(exc))
        speak(VOICE_FEEDBACK_MISUNDERSTOOD_TEXT, turn_id=turn_id, reason="legacy_backend_exception")
        post_voice_event("error", "Voice command failed")


def get_voice_pipeline() -> VoicePipeline:
    if pipeline_cache["pipeline"] is None:
        pipeline_cache["pipeline"] = VoicePipeline()
    return pipeline_cache["pipeline"]


def stop_pipeline_speech(turn_id: str | None = None) -> None:
    pipeline = pipeline_cache.get("pipeline")
    if pipeline is not None:
        try:
            pipeline.stop_speech()
            log_voice_turn(turn_id, "pipeline_speech_stopped")
        except Exception:
            logger.debug("Could not stop current speech", exc_info=True)
            log_voice_turn(turn_id, "pipeline_speech_stop_failed")


def post_voice_event(event_status: str, message: str) -> None:
    try:
        token = get_token()
        with httpx.Client(timeout=5) as client:
            client.post(
                f"{BACKEND_URL}/api/voice/event",
                headers={"Authorization": f"Bearer {token}"},
                json={"status": event_status, "message": message},
            )
    except Exception:
        pass


def get_token() -> str:
    if token_cache["token"] and time.time() - float(token_cache["time"]) < 60 * 60:
        return str(token_cache["token"])
    with httpx.Client(timeout=10) as client:
        response = client.post(
            f"{BACKEND_URL}/api/auth/login",
            json={"username": APP_USERNAME, "password": APP_PASSWORD},
        )
    response.raise_for_status()
    token_cache["token"] = response.json()["access_token"]
    token_cache["time"] = time.time()
    return str(token_cache["token"])


def reset_to_idle(delay_seconds: float = 0, turn_id: str | None = None) -> None:
    if delay_seconds:
        time.sleep(delay_seconds)
    message = "waiting for wake-word"
    status.update(ok=True, state="idle", message=message)
    log_voice_turn(turn_id, "idle_returned", message=message)
    post_voice_event("idle", message)


def drain_audio_queue() -> int:
    dropped = 0
    while True:
        try:
            audio_queue.get_nowait()
            dropped += 1
        except queue.Empty:
            return dropped


def speak(text: str, turn_id: str | None = None, reason: str = "local_feedback") -> None:
    if not VOICE_FEEDBACK_ENABLED or not text:
        log_voice_turn(turn_id, "local_tts_skipped", reason=reason, enabled=VOICE_FEEDBACK_ENABLED)
        return

    command = [VOICE_TTS_COMMAND, "-s", VOICE_TTS_RATE, text]
    env = os.environ.copy()
    if OUTPUT_DEVICE:
        env["AUDIODEV"] = OUTPUT_DEVICE

    try:
        started = time.perf_counter()
        log_voice_turn(turn_id, "local_tts_start", reason=reason, command=VOICE_TTS_COMMAND)
        result = subprocess.run(
            command,
            env=env,
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=8,
        )
        if result.returncode != 0:
            raise RuntimeError(f"{VOICE_TTS_COMMAND} exited with code {result.returncode}")
        log_voice_turn(
            turn_id,
            "local_tts_done",
            reason=reason,
            duration_ms=round((time.perf_counter() - started) * 1000, 2),
        )
    except Exception as exc:
        logger.warning("Voice feedback failed: %s", exc)
        log_voice_turn(turn_id, "local_tts_error", reason=reason, error=str(exc))
