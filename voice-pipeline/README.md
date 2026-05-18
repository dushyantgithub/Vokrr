# Voice Pipeline

The active Vokrr voice runtime is the `voice-listener` Docker service plus the shared modules in `services/`.

## Current Flow

```text
Microphone
-> Porcupine wake word ("Jarvis")
-> one-shot audio capture, max 10 seconds
-> faster-whisper local STT
-> NVIDIA Llama-compatible chat API for intent classification
-> Home Assistant service calls when a device command is detected
-> NVIDIA Magpie TTS
-> ALSA playback through aplay
-> reset to wake-word mode
```

There is no conversation follow-up window in the current implementation. After one command succeeds or fails, the listener returns to `waiting for wake-word`.

## Services

| Path | Purpose |
| --- | --- |
| `voice-pipeline/listener/listener.py` | FastAPI health endpoint, microphone capture, Porcupine, Whisper STT, backend status events |
| `services/voice_pipeline.py` | LLM -> HA -> TTS orchestration |
| `services/nvidia_llm_service.py` | NVIDIA chat completion client |
| `services/nvidia_tts_service.py` | NVIDIA Magpie/Riva TTS client |
| `services/ha_service.py` | HA entity context, aliases, matching, command execution |
| `services/audio_player.py` | aplay/ffplay playback and temp-file cleanup |
| `voice-pipeline/intent/service.py` | Legacy text bridge to backend `/api/voice/command` |

## Required Environment

See [../docs/ENVIRONMENT.md](../docs/ENVIRONMENT.md). The most important values are:

```bash
VOICE_LISTENER_ENABLED=1
VOICE_INPUT_DEVICE=USB Device 0x46d:0x825
PORCUPINE_API_KEY=<picovoice-key>
PORCUPINE_KEYWORD_PATH=/wake-word/Jarvis_en_raspberry-pi_v4_0_0.ppn
NVIDIA_API_KEY=<nvidia-key>
HOME_ASSISTANT_URL=http://localhost:8123
HOME_ASSISTANT_TOKEN=<ha-token>
```

## Build and Run

```bash
docker compose -f infra/docker-compose.yml build voice-listener
docker compose -f infra/docker-compose.yml up -d voice-listener
curl -sS http://localhost:8091/health | python3 -m json.tool
```

## CLI Test

```bash
docker compose -f infra/docker-compose.yml run --rm --no-deps voice-listener \
  python -m services.voice_pipeline --text "turn off bedroom lights" --no-speak
```

## Troubleshooting

See [../docs/TROUBLESHOOTING.md](../docs/TROUBLESHOOTING.md).

