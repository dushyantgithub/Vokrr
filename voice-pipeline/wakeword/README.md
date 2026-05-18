# Wake Word

The active wake-word implementation is Picovoice Porcupine in `voice-pipeline/listener/listener.py`.

Configuration:

```bash
VOICE_WAKE_WORD=Jarvis
PORCUPINE_API_KEY=<picovoice-key>
PORCUPINE_KEYWORD_PATH=/wake-word/Jarvis_en_raspberry-pi_v4_0_0.ppn
```

The wake-word model is mounted into the listener container from `wake-word/`.

openWakeWord is not used by the current runtime.

