You are my senior engineer and system architect. Build this project from scratch in a clean, production-minded way. Do not skip steps. Do not assume old files should be reused. We are starting fresh by wiping the Raspberry Pi, reinstalling the OS, and rebuilding the whole system properly.

PROJECT GOAL
Build a custom smart home control system with:
1. Raspberry Pi 4 (8GB) as the main local server
2. Home Assistant used only as the device/integration engine via APIs
3. A custom touchscreen UI running on the Raspberry Pi attached display
4. Voice control using wake word + commands
5. A local backend that sits between my UI/voice system and Home Assistant
6. A fully local-first architecture
7. Local-network access through the Vokrr app with username/password authentication

The current scope is ONLY:
- Fresh Raspberry Pi setup from scratch
- Home Assistant setup
- Custom backend
- Custom touchscreen UI
- Local network app login for the custom home automation app
- iOS app client for authenticated room/device access
- Wake word + speech command pipeline
- Home Assistant API integration

Do not include any hardware controller other than:
- Raspberry Pi 4 (8GB)
- Touchscreen connected to Raspberry Pi
- Microphone connected to Raspberry Pi
- Speaker connected to Raspberry Pi

PROJECT PRINCIPLES
- Build everything from scratch
- Assume the Raspberry Pi will be wiped fully
- Keep Home Assistant as the device/integration engine only
- Do NOT use Home Assistant as the main user interface
- Build a custom touchscreen UI
- Build a custom local voice pipeline
- Keep the whole system local-first
- Use production-minded architecture
- Use clear folder structure
- Use environment variables for secrets
- Use maintainable code and documentation
- Prefer robust/simple choices over overly clever fragile ones
- Optimize for Raspberry Pi 4 (8GB)
- Minimize unnecessary CPU/RAM usage
- Design the backend so multiple input methods can be added later, but do not mention or implement future hardware in this phase

HIGH LEVEL ARCHITECTURE
- Raspberry Pi 4 (8GB)
  - Fresh OS install
  - Docker / Docker Compose
  - Home Assistant
  - Custom backend service
  - Native Qt/QML touchscreen console
  - Wake word engine
  - Speech-to-text service
  - Text-to-speech service
- Touch UI flow
  - user signs into Vokrr app locally
  - user touches UI on Raspberry Pi display
  - native console calls backend
  - backend calls Home Assistant APIs
  - realtime state reflected back in UI
- iOS flow
  - user opens iOS app
  - user enters server address or uses local discovery
  - user signs in with Vokrr app username/password
  - app stores token securely
  - app loads rooms/devices from backend
  - app controls devices through backend APIs
  - app receives realtime updates over WebSocket
- Voice flow
  - mic connected to Raspberry Pi
  - wake word locally detected
  - once wake word is detected, record speech
  - transcribe locally
  - parse intent in backend
  - call Home Assistant service APIs
  - optionally play TTS response over speaker

TARGET DEVICE CONTROL
The backend should control Home Assistant entities through APIs.
Examples:
- Wipro smart bulbs / tubelights via Home Assistant integrations
- smart plugs via Home Assistant
- future devices via Home Assistant integrations

Do not hardcode only one brand. Build a generic abstraction around:
- rooms
- devices
- device types
- capabilities
- actions

USER EXPERIENCE
1. Touchscreen UI on Raspberry Pi
   - login screen using Vokrr username/password
   - fullscreen kiosk-style app
   - custom modern UI
   - room browsing
   - device list and device cards
   - toggles, brightness sliders, fan speed controls, scene buttons where relevant
   - realtime device state updates
2. Voice
   - wake word
   - natural commands like:
     - turn on bedroom lights
     - turn off living room fan
     - set bedroom light to 50 percent
     - switch on all lights in kitchen
   - backend maps these to Home Assistant actions
   - optional spoken confirmation response
3. iOS App
   - first launch requires login
   - user can access all configured rooms and devices after login
   - device controls use the same backend APIs as the touchscreen UI
   - realtime state updates use the backend WebSocket
   - token is stored in Keychain

TECH STACK DECISIONS
Unless there is a strong technical reason otherwise, use:
- Raspberry Pi OS Lite as the fresh OS
- Docker Compose
- Home Assistant Container if practical, otherwise recommend the best install method and justify it clearly
- Python FastAPI backend
- Qt/QML native console for the touchscreen UI
- Swift + SwiftUI for the iOS app
- WebSocket for realtime native-console/backend updates
- Home Assistant REST + WebSocket APIs
- Python services for voice pipeline orchestration
- SQLite or lightweight local storage only where needed for metadata/cache
- YAML or JSON configs for room/device mapping if needed
- systemd or Docker restart policies for boot persistence

WHAT I WANT YOU TO PRODUCE
I want a full implementation plan and then the codebase structure. Work in phases. Be explicit. Give code, configs, commands, file contents, and explanations where appropriate. I want an implementation-oriented output, not vague advice.

PHASE 0 — FULL RESET AND CLEAN FOUNDATION
Start from absolute scratch.

Tasks:
1. Define exactly how to wipe the Raspberry Pi safely
2. Define which OS to install and why
3. Define how to flash it from another computer
4. Define first boot setup
5. Define SSH setup
6. Define Wi-Fi setup
7. Define static IP recommendation if useful
8. Define system update commands
9. Define base packages to install
10. Define Docker and Docker Compose installation
11. Define directory structure on the Pi for this project

Deliverables:
- exact step-by-step instructions
- exact shell commands
- exact OS recommendation with justification
- exact base system setup instructions

PHASE 1 — SYSTEM ARCHITECTURE AND REPOSITORY STRUCTURE
Design the project repo and codebase layout for:
- backend
- qt-frontend
- voice services
- configuration
- docs
- deployment
- scripts

Expected style:
root/
  backend/
  qt-frontend/
  voice/
  infra/
  docs/
  scripts/
  docker-compose.yml
  .env.example
  README.md

Deliverables:
- final repo structure
- explanation of each folder
- startup/deployment flow
- how services communicate with each other

PHASE 2 — HOME ASSISTANT SETUP AS DEVICE ENGINE
Set up Home Assistant specifically for API-based use.

Goals:
- install and run Home Assistant
- explain whether Home Assistant Container or Home Assistant OS is best in this architecture
- enable long-lived access token flow
- document REST and WebSocket access
- explain how entities and services will be discovered
- create a device abstraction layer in our backend
- do not rely on Home Assistant UI except for initial admin/integration setup

Deliverables:
- setup instructions
- token/config guidance
- example API calls
- plan for mapping Home Assistant entities into our own room/device model
- recommendation on where that mapping should live

PHASE 3 — BACKEND IMPLEMENTATION
Build a FastAPI backend that:
- exposes local app authentication
- connects to Home Assistant
- subscribes to Home Assistant state updates via WebSocket
- exposes REST APIs for native clients
- exposes WebSocket for realtime native-console sync
- contains the voice intent processing pipeline
- contains room/device abstraction
- contains action execution layer
- returns normalized device models to the native console

Required backend modules:
- app auth service
- config loader
- Home Assistant client
- entity registry / room mapping
- WebSocket manager
- device service
- scene/action service
- voice intent parser
- state synchronization service
- health/status endpoints

Example APIs:
- POST /api/auth/login
- GET /api/rooms
- GET /api/rooms/{room_id}
- GET /api/devices
- GET /api/devices/{device_id}
- POST /api/devices/{device_id}/toggle
- POST /api/devices/{device_id}/set
- POST /api/voice/command
- GET /api/system/health

Deliverables:
- detailed backend architecture
- file-by-file implementation plan
- actual starter code
- logging/error-handling strategy
- config format for rooms/devices/capabilities

PHASE 4 — TOUCHSCREEN NATIVE CONSOLE
Build a custom touchscreen UI using Qt/QML.

Requirements:
- login screen using the Vokrr app username/password
- fullscreen kiosk-friendly layout
- optimized for Raspberry Pi attached display
- simple, fast, touch-friendly
- realtime device state updates using backend WebSocket
- room grid screen
- room details screen
- device cards
- toggle controls
- sliders for brightness where applicable
- scene shortcuts
- system status component
- clean modern styling
- responsive layout suitable for the attached display resolution

Need:
- navigation structure
- component structure
- global state management
- API integration layer
- websocket sync layer
- kiosk launch strategy on boot

Deliverables:
- qt-frontend folder structure
- screen/page/component plan
- starter implementation
- instructions to run automatically on boot in kiosk mode
- recommendation for native kiosk setup on Pi

PHASE 4.5 — IOS APP
Build a native iOS client for the local Vokrr backend.

Requirements:
- first-launch login
- manual server URL entry first, Bonjour discovery later
- Keychain token storage
- room list
- device list
- toggle controls
- brightness sliders where applicable
- realtime WebSocket updates
- offline/local-network unavailable state

Deliverables:
- iOS project structure
- API client
- auth/session manager
- room/device models
- SwiftUI screens
- setup instructions for connecting to `http://vokrr.local:8080`

PHASE 5 — VOICE CONTROL PIPELINE
Implement the custom voice path:
- wake word detection locally
- mic input on Raspberry Pi
- record speech after wake word
- transcribe locally
- parse intent in our backend
- call Home Assistant APIs
- optionally respond with local TTS

Important:
- this is NOT Home Assistant Assist as the main controller
- Home Assistant remains the device action layer only
- the voice pipeline should be our own service flow

Use practical local components and justify choices.

Preferred structure:
- wake word engine service
- recording service
- STT service
- intent parser
- action mapper
- TTS responder

Support example commands:
- turn on bedroom lights
- turn off kitchen tubelight
- switch on fan in living room
- set bedroom light to 30 percent
- turn off all lights in office

Need a simple intent format like:
{
  "intent": "device_control",
  "room": "bedroom",
  "device": "light",
  "action": "turn_on",
  "value": null
}

Deliverables:
- recommended wake word engine
- mic setup instructions
- speaker setup instructions
- Python service architecture
- starter code or code stubs for the first usable version
- command parsing strategy
- fallback behavior when intent confidence is low
- local TTS integration strategy

PHASE 6 — DEPLOYMENT AND AUTOSTART
Make the system boot directly into the product experience.

Requirements:
- backend starts on boot
- native Qt console starts on boot
- kiosk opens fullscreen on boot
- voice pipeline starts on boot
- Home Assistant starts on boot
- all services restart automatically on failure
- logs are accessible and clean

Deliverables:
- autostart strategy
- Docker restart policy or systemd units where appropriate
- exact commands/configs
- boot flow explanation

PHASE 7 — TESTING PLAN
Create a proper testing and validation plan.

Need:
- backend API tests
- Home Assistant connectivity tests
- native console interaction tests
- voice pipeline tests
- end-to-end tests for:
  - touch to device control
  - voice to device control
  - realtime state synchronization

Deliverables:
- checklist-style validation plan
- debug strategy
- common failure modes and fixes

PHASE 8 — DOCUMENTATION
Create documentation for:
- setup
- development
- deployment
- configuration
- troubleshooting
- adding new devices
- adding new rooms
- extending voice commands

Deliverables:
- README structure
- docs folder structure
- example docs files

IMPLEMENTATION STYLE
- Give practical commands, file contents, and code
- Prefer incremental milestones
- Explain why each technical choice is made
- Keep the first version lean but correctly structured
- Highlight Pi-specific performance considerations
- Avoid overengineering
- Build a strong foundation first

NOW START BY DOING THE FOLLOWING IN ORDER:
1. Recommend the best installation method for Home Assistant in this architecture and justify it
2. Recommend the exact Raspberry Pi OS/base system setup
3. Propose the repo/folder structure
4. Propose the service architecture
5. Then begin Phase 0 with exact reset and install instructions
