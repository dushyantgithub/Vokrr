import logging
import os
import queue
import random
import subprocess
import threading
import time
import asyncio
from pathlib import Path

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
LISTENER_ENABLED = os.getenv("VOICE_LISTENER_ENABLED", "1") == "1"
INPUT_DEVICE = os.getenv("VOICE_INPUT_DEVICE") or None
OUTPUT_DEVICE = os.getenv("VOICE_OUTPUT_DEVICE") or None
COMMAND_RECORD_SECONDS = float(os.getenv("VOICE_COMMAND_RECORD_SECONDS", "10"))
COMMAND_MIN_SECONDS = float(os.getenv("VOICE_COMMAND_MIN_SECONDS", "1.2"))
COMMAND_SILENCE_SECONDS = float(os.getenv("VOICE_COMMAND_SILENCE_SECONDS", "1.1"))
COMMAND_SILENCE_RMS = int(os.getenv("VOICE_COMMAND_SILENCE_RMS", "450"))
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

audio_queue: queue.Queue[bytes] = queue.Queue()
status = {
    "ok": False,
    "state": "starting",
    "message": "Voice listener starting",
    "wake_word": WAKE_WORD_DISPLAY,
    "wake_engine": "porcupine",
    "stt_engine": "faster-whisper",
    "keyword_path": str(PORCUPINE_KEYWORD_PATH),
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
        audio_queue.put(bytes(indata))

    status.update(
        ok=True,
        state="idle",
        message="waiting for wake-word",
        sample_rate=sample_rate,
        input_sample_rate=input_sample_rate,
        frame_length=frame_length,
        input_device=INPUT_DEVICE or "default",
    )
    post_voice_event("idle", status["message"])

    pending_audio = np.array([], dtype=np.int16)

    def next_porcupine_frame() -> np.ndarray:
        nonlocal pending_audio
        while len(pending_audio) < frame_length:
            chunk = resample_pcm(pcm_from_bytes(audio_queue.get()), input_sample_rate, sample_rate)
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
            while True:
                pcm = next_porcupine_frame()

                result = porcupine.process(pcm)
                if result < 0:
                    continue

                prompt = random.choice(ASSIST_PROMPTS)
                status.update(
                    ok=True,
                    state="listening",
                    message="waiting for command",
                    last_wake=time.time(),
                )
                post_voice_event("listening", "waiting for command")
                stop_pipeline_speech()
                speak(prompt)
                drain_audio_queue()
                pending_audio = np.array([], dtype=np.int16)
                command_audio = record_command(next_porcupine_frame, sample_rate)
                text = transcribe_audio(command_audio, sample_rate)
                status.update(last_text=text)

                if text:
                    submit_command(text)
                    reset_to_idle(delay_seconds=1)
                else:
                    status.update(ok=True, state="idle", message=VOICE_FEEDBACK_MISUNDERSTOOD_TEXT)
                    speak(VOICE_FEEDBACK_MISUNDERSTOOD_TEXT)
                    post_voice_event("error", VOICE_FEEDBACK_MISUNDERSTOOD_TEXT)
                    reset_to_idle(delay_seconds=1.5)
    except Exception as exc:
        status.update(ok=False, state="listener_error", message=str(exc))
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


def record_command(next_frame, sample_rate: int) -> np.ndarray:
    frames: list[np.ndarray] = []
    started_at = time.time()
    last_voice_at = started_at

    status.update(ok=True, state="recording", message="waiting for command")
    post_voice_event("listening", "waiting for command")

    while time.time() - started_at < COMMAND_RECORD_SECONDS:
        pcm = next_frame()

        frames.append(pcm.copy())
        rms = float(np.sqrt(np.mean(np.square(pcm.astype(np.float32)))))
        now = time.time()
        if rms >= COMMAND_SILENCE_RMS:
            last_voice_at = now
        if now - started_at >= COMMAND_MIN_SECONDS and now - last_voice_at >= COMMAND_SILENCE_SECONDS:
            break

    if not frames:
        return np.array([], dtype=np.int16)
    return np.concatenate(frames)


def transcribe_audio(audio: np.ndarray, sample_rate: int) -> str:
    if audio.size == 0:
        return ""

    status.update(ok=True, state="transcribing", message="Transcribing...")
    post_voice_event("processing", "Transcribing...")
    started = time.perf_counter()
    model = load_whisper_model()
    audio_float = audio.astype(np.float32) / 32768.0
    segments, _info = model.transcribe(
        audio_float,
        language=WHISPER_LANGUAGE,
        vad_filter=True,
    )
    text = " ".join(segment.text.strip() for segment in segments).strip()
    status.update(last_stt_duration_ms=round((time.perf_counter() - started) * 1000, 2))
    logger.info("Whisper recognized command: %s", text)
    return text.lower()


def load_whisper_model():
    if whisper_cache["model"] is None:
        status.update(ok=True, state="loading_stt", message=f"Loading Whisper {WHISPER_MODEL_NAME}...")
        from faster_whisper import WhisperModel

        whisper_cache["model"] = WhisperModel(
            WHISPER_MODEL_NAME,
            device=WHISPER_DEVICE,
            compute_type=WHISPER_COMPUTE_TYPE,
        )
    return whisper_cache["model"]


def pcm_from_bytes(data: bytes) -> np.ndarray:
    return np.frombuffer(data, dtype=np.int16)


def submit_command(text: str) -> None:
    status.update(ok=True, state="processing", message=f"Heard: {text}")
    post_voice_event("processing", status["message"])
    if VOICE_NVIDIA_PIPELINE_ENABLED:
        try:
            pipeline = get_voice_pipeline()
            if not pipeline.llm_service.configured or not pipeline.tts_service.configured:
                logger.warning("NVIDIA voice pipeline is enabled but API key is missing")
                raise RuntimeError("NVIDIA API key is missing")
            result = asyncio.run(
                pipeline.handle_text(
                    text,
                    stt_duration_ms=status.get("last_stt_duration_ms"),
                    speak=VOICE_FEEDBACK_ENABLED,
                )
            )
            status.update(
                ok=result.error is None,
                state="idle",
                message=result.reply,
                last_pipeline=result.as_dict(),
            )
            post_voice_event("done" if result.error is None else "error", result.reply)
            return
        except Exception as exc:
            logger.exception("NVIDIA voice pipeline failed; falling back to backend intent")
            status.update(ok=False, state="pipeline_error", message=str(exc))

    try:
        token = get_token()
        with httpx.Client(timeout=20) as client:
            response = client.post(
                f"{BACKEND_URL}/api/voice/command",
                headers={"Authorization": f"Bearer {token}"},
                json={"text": text},
            )
        if response.status_code >= 400:
            status.update(ok=False, state="command_error", message=response.text)
            speak(VOICE_FEEDBACK_MISUNDERSTOOD_TEXT)
            post_voice_event("error", "Voice command failed")
            return
        payload = response.json()
        message = payload.get("message", "Done")
        if not payload.get("understood", False):
            speak(VOICE_FEEDBACK_MISUNDERSTOOD_TEXT)
        status.update(ok=True, state="idle", message=message)
        post_voice_event("done", message)
    except Exception as exc:
        status.update(ok=False, state="command_error", message=str(exc))
        speak(VOICE_FEEDBACK_MISUNDERSTOOD_TEXT)
        post_voice_event("error", "Voice command failed")
    finally:
        reset_to_idle(delay_seconds=2)


def get_voice_pipeline() -> VoicePipeline:
    if pipeline_cache["pipeline"] is None:
        pipeline_cache["pipeline"] = VoicePipeline()
    return pipeline_cache["pipeline"]


def stop_pipeline_speech() -> None:
    pipeline = pipeline_cache.get("pipeline")
    if pipeline is not None:
        try:
            pipeline.stop_speech()
        except Exception:
            logger.debug("Could not stop current speech", exc_info=True)


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


def reset_to_idle(delay_seconds: float = 0) -> None:
    if delay_seconds:
        time.sleep(delay_seconds)
    message = "waiting for wake-word"
    status.update(ok=True, state="idle", message=message)
    post_voice_event("idle", message)


def drain_audio_queue() -> None:
    while True:
        try:
            audio_queue.get_nowait()
        except queue.Empty:
            return


def speak(text: str) -> None:
    if not VOICE_FEEDBACK_ENABLED or not text:
        return

    command = [VOICE_TTS_COMMAND, "-s", VOICE_TTS_RATE, text]
    env = os.environ.copy()
    if OUTPUT_DEVICE:
        env["AUDIODEV"] = OUTPUT_DEVICE

    try:
        subprocess.run(
            command,
            env=env,
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=8,
        )
    except Exception as exc:
        logger.warning("Voice feedback failed: %s", exc)
