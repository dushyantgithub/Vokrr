# Architecture

Vokrr is a local-first home automation console. Home Assistant is the integration engine; Vokrr owns the custom UI, auth, orchestration, voice UX, and device presentation.

## High-Level System

```mermaid
flowchart TB
    subgraph Pi[Raspberry Pi]
        Kiosk[Qt/QML Kiosk]
        Backend[FastAPI Backend]
        HA[Home Assistant]
        Listener[Voice Listener]
        Intent[Legacy Voice Intent Bridge]
        SpotifyConnect[Spotify Connect librespot]
        Data[(SQLite + YAML + token files)]
    end

    Kiosk <-->|REST + WebSocket| Backend
    Listener -->|voice.status events| Backend
    Listener -->|fallback command| Backend
    Intent -->|text command| Backend
    Backend <-->|REST + WebSocket| HA
    Listener -->|REST services + states| HA
    Backend --> Data
    Backend <-->|OAuth/playback| Spotify[Spotify Web API]
    SpotifyClient[Spotify apps] --> SpotifyConnect
    HA --> Devices[Lights, switches, fans, media players]
    Listener <-->|LLM/TTS| NVIDIA[NVIDIA APIs]
```

## Device Control Flow

```mermaid
sequenceDiagram
    participant UI as Qt/iOS client
    participant API as FastAPI backend
    participant DS as DeviceService
    participant HA as Home Assistant
    participant WS as Backend WebSocket

    UI->>API: POST /api/devices/{id}/set
    API->>DS: validate device and capability
    DS->>HA: POST /api/services/{domain}/{service}
    HA-->>DS: service result
    DS->>HA: GET /api/states until expected state or timeout
    DS-->>API: updated Device
    API->>WS: broadcast device.updated
    API-->>UI: updated Device
```

## State Sync Flow

```mermaid
flowchart LR
    HAEvents[HA WebSocket state_changed] --> BackendRegistry[Registry update]
    HARegistry[HA entity_registry_updated] --> Discovery[Schedule discovery/import]
    Timer[Periodic reconcile loop] --> HAStates[GET /api/states]
    Startup[Backend startup] --> StartupSync[import + sync + reconcile with retries]
    HAStates --> BackendRegistry
    Discovery --> Snapshot[Broadcast snapshot]
    BackendRegistry --> DeviceUpdated[Broadcast device.updated]
```

## Home Assistant vs Tuya Routing

```mermaid
flowchart TD
    UserAction[User taps or says command] --> BackendOrVoice{Path}
    BackendOrVoice -->|UI/API| Backend[FastAPI backend]
    BackendOrVoice -->|Voice LLM command| VoiceHA[Voice HA service]
    Backend --> HA[Home Assistant API]
    VoiceHA --> HA
    HA --> Integration{HA integration}
    Integration --> Tuya[Tuya/local-tuya in HA]
    Integration --> Matter[Matter/ESPHome/MQTT/TP-Link/Shelly/etc.]
    Tuya --> Device[Physical device]
    Matter --> Device
```

Current implementation note: Vokrr does not call Tuya cloud APIs directly. Tuya devices must be exposed through Home Assistant.

## Voice Pipeline

```mermaid
sequenceDiagram
    participant User
    participant Listener as voice-listener
    participant STT as faster-whisper
    participant LLM as NVIDIA Llama API
    participant HA as Home Assistant
    participant TTS as NVIDIA Magpie TTS
    participant UI as Backend/Qt status pill

    Listener->>UI: idle / waiting for wake-word
    User->>Listener: "Jarvis"
    Listener->>UI: listening / waiting for command
    Listener->>User: wake feedback
    User->>Listener: one command
    Listener->>STT: recorded audio, max 10s
    STT-->>Listener: text
    Listener->>UI: processing
    Listener->>LLM: text + HA entity context
    LLM-->>Listener: strict JSON decision
    alt Home automation command
        Listener->>HA: service call(s)
        HA-->>Listener: result
    else Conversation or error
        Listener->>Listener: build short reply
    end
    Listener->>TTS: reply text
    TTS-->>Listener: wav audio
    Listener->>User: play audio
    Listener->>UI: done/error
    Listener->>UI: idle / waiting for wake-word
```

## Raspberry Pi Boot/Startup Flow

```mermaid
flowchart TD
    Boot[Pi boots] --> NetworkManager[NetworkManager]
    NetworkManager --> WiFi[vokrr-wifi.service]
    WiFi --> Docker[docker.service]
    Docker --> Stack[vokrr-stack.service]
    Stack --> Compose[Home Assistant, backend, voice, Spotify, cloudflared]
    Compose --> BackendReady[Backend /api/system/health ready]
    BackendReady --> LightDM[graphical.target/lightdm]
    LightDM --> Kiosk[vokrr-kiosk.service]
    Kiosk --> Qt[qt-frontend/build/vokrr-qt fullscreen]
```

## Persistence

| Path | Purpose |
| --- | --- |
| `home-assistant/config/` | Home Assistant configuration and Vokrr YAML registry |
| `backend/data/auth.db` | Vokrr users, sessions, activity |
| `backend/data/onboarding.db` | Imported Home Assistant devices |
| `backend/data/spotify_tokens.json` | Spotify OAuth tokens |
| `backend/data/audio-output.env` | Detected ALSA playback device |
| `backend/data/librespot-*` | Spotify Connect cache |

