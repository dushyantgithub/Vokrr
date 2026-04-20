import json
import os
import queue
import random
import threading
import time
from pathlib import Path

import httpx
from fastapi import FastAPI

BACKEND_URL = os.getenv("VOICE_BACKEND_URL", "http://localhost:8080").rstrip("/")
APP_USERNAME = os.getenv("APP_USERNAME", "admin")
APP_PASSWORD = os.getenv("APP_PASSWORD", "")
WAKE_WORD = os.getenv("VOICE_WAKE_WORD", "quantum").lower()
WAKE_WORD_DISPLAY = os.getenv("VOICE_WAKE_WORD", "quantum")
MODEL_PATH = Path(os.getenv("VOSK_MODEL_PATH", "/models/vosk"))
LISTENER_ENABLED = os.getenv("VOICE_LISTENER_ENABLED", "1") == "1"
SAMPLE_RATE = int(os.getenv("VOICE_SAMPLE_RATE", "16000"))
INPUT_DEVICE = os.getenv("VOICE_INPUT_DEVICE") or None
COMMAND_WINDOW_SECONDS = int(os.getenv("VOICE_COMMAND_WINDOW_SECONDS", "30"))
ASSIST_PROMPTS = [
    "How can I help, sir?",
    "Listening, sir.",
    "What should I do next?",
    "Ready for your command.",
]

app = FastAPI(title="Quantum Home Voice Listener", version="0.1.0")

audio_queue: queue.Queue[bytes] = queue.Queue()
status = {
    "ok": False,
    "state": "starting",
    "message": "Voice listener starting",
    "wake_word": WAKE_WORD_DISPLAY,
    "model_path": str(MODEL_PATH),
}
token_cache = {"token": None, "time": 0.0}


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
        import sounddevice as sd
        from vosk import KaldiRecognizer, Model
    except Exception as exc:
        status.update(ok=False, state="dependency_error", message=str(exc))
        return

    if not MODEL_PATH.exists():
        status.update(
            ok=False,
            state="model_missing",
            message=f"Vosk model missing at {MODEL_PATH}. Download a model before enabling voice.",
        )
        return

    try:
        sample_rate = select_sample_rate(sd)
    except Exception as exc:
        status.update(ok=False, state="audio_error", message=str(exc))
        post_voice_event("error", status["message"])
        return

    try:
        model = Model(str(MODEL_PATH))
        recognizer = KaldiRecognizer(model, sample_rate)
        recognizer.SetWords(False)
    except Exception as exc:
        status.update(ok=False, state="model_error", message=str(exc))
        return

    def callback(indata, frames, time_info, error) -> None:
        if error:
            status.update(ok=False, state="audio_error", message=str(error))
        audio_queue.put(bytes(indata))

    status.update(
        ok=True,
        state="idle",
        message=f"Listening for {WAKE_WORD_DISPLAY}",
        sample_rate=sample_rate,
        input_device=INPUT_DEVICE or "default",
    )
    post_voice_event("idle", status["message"])

    waiting_for_command_until = 0.0
    try:
        with sd.RawInputStream(
            samplerate=sample_rate,
            blocksize=8000,
            dtype="int16",
            channels=1,
            device=INPUT_DEVICE,
            callback=callback,
        ):
            while True:
                data = audio_queue.get()
                if waiting_for_command_until and time.time() > waiting_for_command_until:
                    waiting_for_command_until = 0.0
                    status.update(ok=True, state="idle", message=f"Listening for {WAKE_WORD_DISPLAY}")
                    post_voice_event("idle", status["message"])
                    recognizer.Reset()
                    continue
                if not recognizer.AcceptWaveform(data):
                    continue
                result = json.loads(recognizer.Result())
                text = result.get("text", "").strip().lower()
                if not text:
                    continue

                if waiting_for_command_until:
                    submit_command(text)
                    waiting_for_command_until = 0.0
                    recognizer.Reset()
                    continue

                if WAKE_WORD in text:
                    command = text.split(WAKE_WORD, 1)[1].strip(" ,")
                    prompt = random.choice(ASSIST_PROMPTS)
                    status.update(ok=True, state="listening", message=prompt)
                    post_voice_event("listening", prompt)
                    if command:
                        submit_command(command)
                        recognizer.Reset()
                    else:
                        waiting_for_command_until = time.time() + COMMAND_WINDOW_SECONDS
                else:
                    status.update(ok=True, state="idle", message=f"Listening for {WAKE_WORD_DISPLAY}")
    except Exception as exc:
        status.update(ok=False, state="listener_error", message=str(exc))
        post_voice_event("error", status["message"])


def select_sample_rate(sd) -> int:
    candidate_rates = []
    for rate in [SAMPLE_RATE, 48000, 44100, 16000, 8000]:
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


def submit_command(text: str) -> None:
    status.update(ok=True, state="processing", message=f"Heard: {text}")
    post_voice_event("processing", status["message"])
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
            post_voice_event("error", "Voice command failed")
            return
        message = response.json().get("message", "Done")
        status.update(ok=True, state="idle", message=message)
        post_voice_event("done", message)
    except Exception as exc:
        status.update(ok=False, state="command_error", message=str(exc))
        post_voice_event("error", "Voice command failed")


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
    token_cache["token"] = response.json()["token"]
    token_cache["time"] = time.time()
    return str(token_cache["token"])
