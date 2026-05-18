# Speech To Text

The current STT implementation is inside `voice-pipeline/listener/listener.py` and uses `faster-whisper`.

Configuration:

```bash
WHISPER_MODEL=base.en
WHISPER_LANGUAGE=en
WHISPER_DEVICE=cpu
WHISPER_COMPUTE_TYPE=int8
```

This directory remains as a placeholder for future STT service separation. Vosk is not used by the active runtime.

