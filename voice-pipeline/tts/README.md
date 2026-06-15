# Text To Speech

The active TTS implementation is NVIDIA Magpie through `services/nvidia_tts_service.py`.

Configuration:

```bash
NVIDIA_TTS_FUNCTION_ID=877104f7-e885-42b9-8de8-f6e4c6303969
NVIDIA_TTS_GRPC_SERVER=grpc.nvcf.nvidia.com:443
NVIDIA_TTS_DEFAULT_VOICE=Magpie-Multilingual.EN-US.Aria
NVIDIA_TTS_LANGUAGE_CODE=en-US
NVIDIA_TTS_SAMPLE_RATE_HZ=44100
VOICE_TTS_FALLBACK_ENABLED=1
```

Playback is handled by `services/audio_player.py` using `aplay` when available, with `ffplay` as fallback.

Assistant replies go through NVIDIA Magpie by default. Command-based fallback TTS only runs after
the Magpie API fails, and fallback usage is logged with the voice turn id.

Simple local feedback speech still uses `VOICE_TTS_COMMAND` for wake/misunderstood prompts.
