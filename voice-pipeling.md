You are working on my Vokrr Raspberry Pi voice assistant project.

IMPORTANT:
This implementation must feel ultra fast and realtime like Alexa/Google Assistant.
Optimize everything for low latency and streaming responses.

Current existing pipeline:
- User speaks into microphone
- Raspberry Pi already runs local Whisper STT
- Whisper generates text successfully

New required architecture:

User Voice
→ Whisper STT (local Raspberry Pi)
→ NVIDIA Llama 4 Maverick API
→ Decide:
   A. Home Assistant command
   B. Normal conversation
→ If HA command:
   Execute Home Assistant API call
   Generate short spoken confirmation
→ If normal conversation:
   Generate conversational reply
→ Send final reply text to NVIDIA Magpie TTS API
→ Generate speech
→ Play audio through Raspberry Pi speaker

DO NOT remove or rewrite the existing Whisper STT implementation.
Integrate AFTER STT text is generated.

====================================================
NVIDIA LLM API
====================================================

Use this API structure:

```python
import requests

invoke_url = "https://integrate.api.nvidia.com/v1/chat/completions"
stream = True

headers = {
  "Authorization": f"Bearer {NVIDIA_API_KEY}",
  "Accept": "text/event-stream" if stream else "application/json",
  "Content-Type": "application/json"
}

payload = {
  "model": "meta/llama-4-maverick-17b-128e-instruct",
  "messages": [
    {
      "role": "system",
      "content": SYSTEM_PROMPT
    },
    {
      "role": "user",
      "content": USER_TEXT
    }
  ],
  "max_tokens": 256,
  "temperature": 0.2,
  "top_p": 1.0,
  "stream": True
}

response = requests.post(
    invoke_url,
    headers=headers,
    json=payload,
    stream=True
)

====================================================
NVIDIA MAGPIE TTS

Use NVIDIA hosted Magpie multilingual TTS API.
DO NOT download or run local TTS models.

Reference:
https://build.nvidia.com/nvidia/magpie-tts-multilingual/api

Use NVIDIA cloud endpoint.

Use:

* gRPC client OR
* HTTP endpoint if available

Implementation must support:

* streaming audio if possible
* low latency playback
* temporary wav generation
* automatic cleanup

Default voice:
Magpie-Multilingual.EN-US.Aria

TTS requirements:

* multilingual support
* fast playback
* realtime feel
* short startup delay

====================================================
PROJECT STRUCTURE

Create clean modular services:
services/
  stt_service.py
  nvidia_llm_service.py
  nvidia_tts_service.py
  ha_service.py
  audio_player.py
  voice_pipeline.py

  ====================================================
ENV VARIABLES

Create/update .env

NVIDIA_API_KEY=
NVIDIA_LLM_MODEL=meta/llama-4-maverick-17b-128e-instruct
NVIDIA_LLM_URL=https://integrate.api.nvidia.com/v1/chat/completions

NVIDIA_TTS_FUNCTION_ID=877104f7-e885-42b9-8de8-f6e4c6303969
NVIDIA_TTS_GRPC_SERVER=grpc.nvcf.nvidia.com:443
NVIDIA_TTS_DEFAULT_VOICE=Magpie-Multilingual.EN-US.Aria

Never hardcode credentials.

====================================================
LLAMA SYSTEM PROMPT

Use this exact system prompt:

You are Vokrr, a smart realtime home automation voice assistant.

You must classify whether the user wants:
1. normal conversation
2. home automation action

You MUST return ONLY valid JSON.

Never return markdown.
Never explain.
Never add extra text.

Schema:

{
  "ha_command": true,
  "reply": "short response to speak",
  "intent": "conversation | control_device | query_device_state | unknown",
  "room": "string or null",
  "device_name": "string or null",
  "domain": "light | switch | fan | climate | media_player | cover | unknown | null",
  "action": "turn_on | turn_off | toggle | set_brightness | set_speed | set_temperature | get_state | unknown | null",
  "value": null,
  "confidence": 0.95,
  "needs_confirmation": false,
  "needs_clarification": false,
  "clarification_question": null
}

Rules:
- If user is casually talking, set ha_command=false
- If user asks to control a smart device, set ha_command=true
- Keep spoken replies short
- Never guess unknown devices
- Ask clarification if uncertain
- Dangerous actions require confirmation
- Output ONLY JSON

====================================================
HA ENTITY CONTEXT

Before sending prompt to Llama:
Fetch current Home Assistant entities.

Pass simplified context into prompt:

{
  "available_devices": [
    {
      "entity_id": "switch.hall_fan",
      "name": "Fan",
      "room": "Hall",
      "domain": "switch",
      "state": "off"
    }
  ]
}

LLM should use this context.

Backend MUST still validate matches safely.

====================================================
HA COMMAND EXECUTION

Implement mappings:

turn_on
→ POST /api/services/{domain}/turn_on

turn_off
→ POST /api/services/{domain}/turn_off

toggle
→ POST /api/services/{domain}/toggle

set_brightness
→ light.turn_on with brightness_pct

set_speed
→ fan.set_percentage

set_temperature
→ climate.set_temperature

====================================================
PIPELINE LOGIC

Flow:

1. User speaks
2. Whisper STT returns text
3. Send text + HA entities to Llama
4. Parse strict JSON
5. Validate intent
6. If clarification needed:
    → speak clarification
7. If HA command:
    → execute HA action
    → generate confirmation text
8. Send final text to Magpie TTS
9. Play generated speech immediately

====================================================
AUDIO PLAYBACK

Create:
audio_player.py

Requirements:

* Raspberry Pi compatible
* use aplay if available
* fallback to ffplay
* non-blocking playback
* stop previous speech if user talks again
* automatic cleanup of temp files

====================================================
LOW LATENCY REQUIREMENTS

Must optimize for speed.

Implement:

* async execution
* streaming LLM responses
* short replies
* low temperature
* entity caching
* minimal blocking
* playback immediately after TTS generation
* interruption handling
* concurrency safe design

====================================================
LATENCY LOGGING

Log timings:
STT duration
LLM duration
HA duration
TTS duration
Playback start delay
Total roundtrip

====================================================
FAILURE HANDLING

If LLM fails:
Speak:
“I’m having trouble thinking right now.”

If TTS fails:
Print text in console/UI.

If HA fails:
Speak:
“I could not control that device.”

Never crash pipeline.

====================================================
CLI TEST MODE

Implement:
python -m services.voice_pipeline --text "turn on hall fan"
python -m services.voice_pipeline --text "what can you do?"
python -m services.voice_pipeline --text "switch off bedroom light"

CLI should show:

* parsed JSON
* entity match
* HA result
* TTS output path
* latency breakdown

====================================================
IMPORTANT IMPLEMENTATION NOTES

* Preserve current Whisper STT
* Do not rewrite whole project
* Keep modular architecture
* Add detailed comments
* Use proper async patterns
* Use structured logging
* Keep responses short and natural
* Prioritize responsiveness over long replies

====================================================
AFTER IMPLEMENTATION

Tell me:

1. files changed
2. dependencies installed
3. exact commands to run
4. how to test microphone pipeline
5. how to test CLI mode
6. assumptions made
7. if Magpie endpoint needs any manual configuration
8. how to change voices/languages