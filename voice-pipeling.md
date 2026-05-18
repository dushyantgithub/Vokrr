# Archived Voice Pipeline Prompt

This file contains the original prompt used to implement the NVIDIA voice pipeline. It is intentionally preserved as historical context.

Current maintained voice documentation:

- [voice-pipeline/README.md](voice-pipeline/README.md)
- [docs/SOFTWARE_STACK.md](docs/SOFTWARE_STACK.md)
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- [docs/ENVIRONMENT.md](docs/ENVIRONMENT.md)
- [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)

Current behavior:

- Wake word: Picovoice Porcupine, `Jarvis`
- STT: local faster-whisper
- LLM: NVIDIA Llama-compatible chat completions
- TTS: NVIDIA Magpie
- Command window: one utterance, max 10 seconds
- After any command success/failure, the listener returns to wake-word mode
