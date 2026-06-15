# Wake Word

The active wake-word implementation is Picovoice Porcupine in `voice-pipeline/listener/listener.py`.

Configuration:

```bash
VOICE_WAKE_WORD=Jarvis
PORCUPINE_API_KEY=<picovoice-key>
PORCUPINE_KEYWORD_PATH=/wake-word/Jarvis_en_raspberry-pi_v4_0_0.ppn
PORCUPINE_SENSITIVITY=0.35
VOICE_WAKE_COOLDOWN_SECONDS=2.5
VOICE_WAKE_MIN_RMS=350
VOICE_WAKE_MIN_PEAK_RMS=650
```

The wake-word model is mounted into the listener container from `wake-word/`.

The listener also pauses microphone capture during feedback/TTS playback, drains queued audio
between turns, and rejects wake hits that arrive during cooldown or below the configured energy
gate.

openWakeWord is not used by the current runtime.
