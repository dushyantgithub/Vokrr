# Voice Pipeline

The current voice implementation starts with a small intent bridge. It accepts text commands and forwards them to the backend intent parser at `/api/voice/command`.

This keeps the first running build simple:

1. Wake word service detects the wake phrase locally.
2. STT service converts speech to text locally.
3. Intent bridge submits text to the backend.
4. Backend maps the command to configured Home Assistant entities.
5. TTS service can speak the backend response.

The `wakeword`, `stt`, and `tts` folders are reserved for the next phase once microphone and speaker verification is complete on the Pi.

