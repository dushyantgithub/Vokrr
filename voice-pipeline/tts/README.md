# Text To Speech

The active TTS implementation is NVIDIA Magpie through `services/nvidia_tts_service.py`.

Configuration:

```bash
NVIDIA_TTS_FUNCTION_ID=877104f7-e885-42b9-8de8-f6e4c6303969
NVIDIA_TTS_GRPC_SERVER=grpc.nvcf.nvidia.com:443
NVIDIA_TTS_DEFAULT_VOICE=Magpie-Multilingual.EN-US.Aria
NVIDIA_TTS_LANGUAGE_CODE=en-US
NVIDIA_TTS_SAMPLE_RATE_HZ=44100
```

Playback is handled by `services/audio_player.py` using `aplay` when available, with `ffplay` as fallback.

Simple local feedback speech still uses `VOICE_TTS_COMMAND` for wake/misunderstood prompts.

