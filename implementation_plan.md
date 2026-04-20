# Quantum Home – Foundation Plan

## 1. Home Assistant Installation Method
- **Recommendation:** Home Assistant Container managed through Docker Compose on Raspberry Pi OS Lite (64-bit).
- **Why not Home Assistant OS/Supervised:** Those variants assume the Pi is fully dedicated to Home Assistant and restrict the ability to run custom containers/UIs/voice stack alongside HA under our control. We need a flexible platform hosting FastAPI, React UI assets, wake-word/STT/TTS services, and custom orchestration, so we cannot surrender host management to Home Assistant OS.
- **Benefits of the container approach:**
  - Uses the upstream Docker image maintained by Nabu Casa with ARM64 support, so we still receive official updates and integrations.
  - Compose lets us pin versions, manage environment files, share volumes, and control resource limits per service (critical on the Pi 4).
  - Keeps the host OS consistent with the rest of the stack (systemd/kiosk setup) and simplifies backup (bind-mounted config volumes).

## 2. Base Raspberry Pi OS / System Setup
- **OS Image:** Raspberry Pi OS Lite 64-bit (Debian Bookworm base). Lite keeps the footprint small while 64-bit is required by many modern Home Assistant and ML/voice components.
- **Flashing on workstation:**
  1. Install Raspberry Pi Imager.
  2. Select Raspberry Pi OS Lite (64-bit) → pick SD card → click the gear icon.
  3. Enable SSH, set username/password (e.g., `homeops`), configure Wi-Fi SSID/passphrase and locale, optionally pre-set hostname (`quantum-home`).
  4. Write the image and safely eject the card.
- **First boot checklist:**
  - Insert the card, connect Ethernet (preferred) or ensure Wi-Fi credentials were baked in, power on.
  - Discover IP via router UI or `ping quantum-home.local`.
  - SSH: `ssh homeops@quantum-home.local`.
  - Run `sudo raspi-config` if further locale/keyboard adjustments are needed; set GPU memory to 256 MB for kiosk graphics.
- **Wi-Fi & Static IP:**
  - To edit Wi-Fi manually, modify `/etc/wpa_supplicant/wpa_supplicant.conf`.
  - Prefer DHCP reservation on the router. If you must set static IP on the Pi, add to `/etc/dhcpcd.conf`:
    ```
    interface eth0
        static ip_address=192.168.1.50/24
        static routers=192.168.1.1
        static domain_name_servers=192.168.1.1
    ```

### 2.1 Waveshare 70H-1024600 Touchscreen Setup
The display uses HDMI for video (1024×600 @ 60 Hz) and USB for touch. Configure it immediately after the first system upgrade so the UI stack can run native resolution and accurate touch mapping.

1. **Enable the correct resolution** (`sudo nano /boot/config.txt`):
   ```
   hdmi_force_hotplug=1
   hdmi_group=2
   hdmi_mode=87
   hdmi_cvt=1024 600 60 6 0 0 0
   max_framebuffer_width=1024
   max_framebuffer_height=600
   framebuffer_width=1024
   framebuffer_height=600
   hdmi_drive=1
   dtoverlay=vc4-kms-v3d
   ```
   - Save, exit, then reboot: `sudo reboot`.
2. **Confirm display timing:** after reboot run `tvservice -s` (should show 1024×600). If blank, ensure HDMI cable is connected before boot.
3. **Install touch/GUI dependencies:**
   ```bash
   sudo apt install -y xserver-xorg x11-xserver-utils xinput xinput-calibrator \
       chromium-browser openbox lightdm xserver-xorg-input-libinput
   ```
4. **Calibrate touch (only if touches do not line up):**
   ```bash
   export DISPLAY=:0
   sudo xinput_calibrator
   ```
   - Copy the generated `Section "InputClass"` snippet into `/etc/X11/xorg.conf.d/99-waveshare-touch.conf` (create directory if missing) to persist calibration.
5. **Ensure USB touch recognized:** `lsusb` should show a Waveshare/ILITEK device. Verify input: `xinput list` → note device name → `xinput test <id>`.
6. **Rotate orientation if required:**
   - For landscape kiosk, set `Option "TransformationMatrix" "1 0 0 0 1 0 0 0 1"` in the calibration file.
7. **Test end-to-end:** start X temporarily and open Chromium to confirm multi-touch/mouse interactions: `startx /usr/bin/chromium-browser --start-fullscreen`.

## 3. System Updates & Base Packages
Run immediately after first login.
```bash
sudo apt update
sudo apt full-upgrade -y
sudo rpi-eeprom-update -a
sudo reboot
sudo apt install -y git curl unzip htop tmux python3-pip python3-venv \
    build-essential pkg-config libssl-dev libffi-dev libatlas-base-dev \
    portaudio19-dev libportaudio2 libasound-dev jq cmake ufw
```
- GUI/touch prerequisites are already covered in Section 2.1.
- Enable firewall baseline:
  ```bash
  sudo ufw allow OpenSSH
  sudo ufw enable
  ```

## 4. Docker & Compose Installation
```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker homeops
sudo systemctl enable docker
sudo apt install -y docker-compose-plugin
```
Log out/in so the `homeops` user can run Docker without sudo.

## 5. Repository / Folder Structure
```
quantum-home/
├── backend/                  # FastAPI service
│   ├── app/
│   ├── tests/
│   └── pyproject.toml
├── frontend/                 # React + Vite UI
│   ├── src/
│   └── package.json
├── voice-pipeline/           # Wake-word, STT, TTS microservices
│   ├── wakeword/
│   ├── stt/
│   ├── intent/
│   └── tts/
├── home-assistant/           # compose config, secrets templates, automations
│   └── configuration/
├── infra/
│   ├── docker-compose.yml    # orchestrates HA + backend + voice + frontend runtime
│   ├── env/
│   └── systemd/              # kiosk + service units
├── docs/
│   ├── setup/
│   ├── deployment/
│   ├── troubleshooting/
│   └── README.md
├── scripts/                  # helper scripts (bootstrap, tests, health checks)
└── Makefile                  # top-level automation entry points
```

## 6. Service Architecture Overview
- **Home Assistant (Docker container):** runs integrations, exposes REST/WebSocket APIs. Mount `/homeops/quantum-home/home-assistant/config` for persistence. Home Assistant remains the device/integration engine and is not the primary UI.
- **Backend (FastAPI + async workers):** modules for local app authentication, device abstraction, HA client, intent handler, WebSocket broadcaster. Uses YAML/JSON metadata for rooms/devices and may add SQLite later for user/session metadata if needed.
- **Frontend (React/Vite):** kiosk web app talking to the backend via authenticated REST + WebSocket for realtime state.
- **iOS App (Swift/SwiftUI, planned):** native local-network client that discovers or accepts the Quantum Home server address, requires username/password login on first launch, stores the issued app token in Keychain, then displays the same rooms/devices/actions exposed by the backend.
- **Voice Pipeline:** wake-word engine (Porcupine/openWakeWord), recorder, STT (Vosk/Coqui), intent parser, TTS (Piper) as separate Python services communicating over gRPC/HTTP.
- **Shared infrastructure:** Compose-defined network, `.env` files for secrets, Docker logging routed to journald, optional systemd units for kiosk and Compose stack autostart.

### 6.1 Local Network Exposure & App Login
- Quantum Home is exposed on the local network through the Raspberry Pi hostname/IP:
  - Touchscreen/web UI: `http://quantum-home.local:3000`
  - Backend API: `http://quantum-home.local:8080`
  - Home Assistant admin/setup UI: `http://quantum-home.local:8123`
- Normal users should use the Quantum Home app login, not the Home Assistant UI. Home Assistant credentials remain for administrator setup/integrations only.
- The backend owns the Quantum Home username/password credentials via environment variables:
  - `APP_USERNAME`
  - `APP_PASSWORD`
  - `APP_AUTH_SECRET`
- Web UI and future iOS clients authenticate with `POST /api/auth/login`, receive a signed local token, and pass it to protected backend APIs with `Authorization: Bearer <token>`.
- WebSocket clients pass the same token when connecting so realtime state updates are limited to signed-in clients.
- This is local-first authentication for a trusted LAN. Before any internet exposure, add HTTPS, stronger user management, rate limiting, and a proper reverse proxy.

## 7. Phase 0 – Reset & Install Execution (In Progress)
Follow these steps now that the touchscreen is connected:

1. **Prep Workstation & Downloads**
   - Install Raspberry Pi Imager, gather Wi-Fi credentials, plan secure passwords.
2. **Wipe & Flash microSD** (per Section 2) ensuring hostname `quantum-home` and SSH enabled.
3. **Boot & Network**
   - Attach Waveshare HDMI + USB before powering on so the Pi negotiates the custom resolution.
   - SSH into the Pi, change default password, optionally create secondary admin user.
4. **Apply System Updates & Firmware** using commands from Section 3.
5. **Configure Touchscreen** using Section 2.1 steps immediately after the first reboot so calibration persists before kiosk setup.
6. **Install Base Tooling** (Section 3) and **Docker + Compose** (Section 4).
7. **Project Checkout**
   ```bash
   mkdir -p ~/Projects && cd ~/Projects
   git clone <repo-url> quantum-home
   cd quantum-home
   ```
8. **Hardware Verification**
   - Display/touch: `xinput list`, run Chromium fullscreen test.
   - Microphone: `arecord -l` then `arecord -d 5 test.wav`; playback with `aplay test.wav`.
   - Speaker: `speaker-test -c2 -twav` to confirm output.
9. **Security Baseline** already set with UFW; consider SSH key auth and disable password login once confident.

With Phase 0 actively underway per the checklist above, the Raspberry Pi will exit this phase with a clean OS, Waveshare touchscreen calibrated at 1024×600, Docker/Compose installed, security hardened, and the repository ready for subsequent phases (Home Assistant containerization, backend/frontend scaffolding, voice pipeline, kiosk autostart, etc.).

## 8. Phase 0 Automation Script
A helper script now lives at `scripts/phase0_setup.sh`. Run it locally on the Pi to execute the repeatable parts of Phase 0 (system upgrades, package install, HDMI block, Docker setup).

### Usage
```bash
cd ~/Projects/quantum-home
sudo PI_USER=$USER ./scripts/phase0_setup.sh
```
- `PI_USER` defaults to `homeops`; override if your login differs so the script can add you to the `docker` group.
- Script actions: `apt update/full-upgrade`, EEPROM refresh, installs base + kiosk packages, configures UFW for SSH, appends the Waveshare HDMI block to `/boot/config.txt` if missing, installs Docker + Compose.
- Reboot afterward to apply GPU/firmware changes.

### Manual steps that remain
1. Touch calibration (`xinput_calibrator`) and saving 99-waveshare conf if the pointer is offset.
2. Microphone/speaker verification commands.
3. Repository cloning (if not already done) and SSH key hardening.
4. Any environment-specific network/static-IP configurations beyond the defaults.

Once the script finishes and the Pi reboots cleanly, Phase 0 is considered complete and we can proceed to Phase 1 (Home Assistant deployment).

## 9. Added Scope – iOS App

The iOS app is a native companion for the same local-first backend. It never talks to Home Assistant directly. It targets feature parity with the touchscreen UI and mirrors its visual language (glass surfaces, audio‑reactive aurora background, Jarvis status bar).

### 9.1 Requirements

1. First launch asks for (or discovers) the Quantum Home server address, defaulting to `http://quantum-home.local:8080`.
2. User signs in with the Quantum Home app username/password (not Home Assistant credentials).
3. The returned token is stored in Keychain; subsequent launches attempt it against `/api/system/health` before showing login.
4. The app loads rooms, devices, scenes/routines, and system health from the backend, and controls devices through the same action APIs used by the touchscreen UI.
5. The app subscribes to the backend WebSocket for live state, voice, and scene events.
6. The app handles offline/local-network-unavailable states clearly (banner + retry) and never silently hangs on a dead server.
7. The app follows the touchscreen UI visual language: glass (translucent blurred) cards and chrome, an audio-reactive aurora background, a Jarvis status bar in the nav, a notifications feed, and an embedded News view.

### 9.2 Feature Parity With The Touchscreen UI

The iOS app should render each of the touchscreen's primary views. The navigation surface is a bottom tab bar (`Dashboard`, `Devices`, `Routines`, `Activity`, `News`, `Settings`) on iPhone and a `NavigationSplitView` sidebar on iPad, matching the touchscreen's `Sidebar`.

| Touchscreen surface | iOS implementation |
| --- | --- |
| Dashboard hero device card with brightness/colour/percentage | Large `DeviceCard` (Metal/SwiftUI) with a slider, colour temperature chips, and power toggle. |
| `DeviceTile` grid (per-room) | `LazyVGrid` of glass tiles with long-press for detail. |
| Dimmable `LightRow` list | `LightRow` view with inline brightness slider. |
| `RoomTabs` | Horizontal `ScrollView` of chips above the dashboard content. |
| `DevicesView` | All devices grid with search/filter. |
| `RoutinesView` (`scenes`) | Grid of scene cards that post `POST /api/scenes/{id}/run`. |
| `ActivityView` (health, assistant state, device counts) | Grid of status cards. |
| `NewsView` (embedded `worldmonitor.app`) | `WKWebView` loading `https://www.worldmonitor.app` directly — WKWebView is not subject to the X‑Frame-Options / frame-ancestors restrictions the web iframe is, so the nginx proxy is **not** required from iOS. |
| `Header` Jarvis status bar | Top-safe-area overlay showing `JARVIS_STATUS_LABELS` states (`idle`, `listening`, `processing`, `done`, `error`, `command_error`) plus transcribed STT text. |
| Notifications bell + dropdown | Toolbar bell button + modal/side sheet with recent entries (device updates, voice errors, scene runs). |
| Settings popover (`Hard refresh`, `Sign out`) | Settings tab with server address, account, cache clear (equivalent to hard refresh: purges `URLCache.shared`, in-memory snapshots, `WKWebsiteDataStore` for News), `Sign out`. |
| `SoftAurora` background | Metal shader port of the same GLSL used in `frontend/src/components/SoftAurora/SoftAurora.jsx` with `uNoiseAmp` / `uBandHeight` driven by live mic RMS. |
| Voice command → `navigate` view switch | WebSocket handler switches the selected tab when `voice.command.navigate` is a known view. |

### 9.3 Recommended iOS Stack

- Swift 5.10+, iOS 17 deployment target.
- SwiftUI for all UI; `@Observable` / `Observation` for state, `NavigationStack` + `TabView` (or `NavigationSplitView` on iPad).
- `URLSession` (async/await) for REST, `URLSessionWebSocketTask` for the realtime feed.
- `AVFoundation` (`AVAudioEngine` + `AVAudioPCMBuffer`) for the mic-reactive background level.
- `MetalKit` (`MTKView`) for the `SoftAurora` shader, or fall back to SwiftUI `Canvas` + `TimelineView` if Metal is unavailable.
- `WebKit` (`WKWebView`) for the News tab.
- `Keychain Services` (wrapped in a small `KeychainClient`) for the auth token and server address.
- `Network.framework` + `NWPathMonitor` for offline detection; `Bonjour`/`NWBrowser` for mDNS discovery of `_quantum-home._tcp.local.` once the backend advertises it.
- `os.Logger` + `OSLogStore` for diagnostics.

### 9.4 App Module Layout

```
QuantumHomeiOS/
├── App/
│   ├── QuantumHomeApp.swift            # @main, scene setup, environment injection
│   └── AppState.swift                  # @Observable root store (rooms, devices, scenes, voice, notifications, health)
├── Networking/
│   ├── APIClient.swift                 # async REST calls, token header injection
│   ├── Endpoints.swift                 # strongly typed paths + payloads
│   ├── RealtimeClient.swift            # URLSessionWebSocketTask lifecycle + event decoding
│   └── ServerDiscovery.swift           # NWBrowser Bonjour + manual entry fallback
├── Auth/
│   ├── KeychainClient.swift
│   └── LoginViewModel.swift
├── Models/
│   ├── Room.swift
│   ├── Device.swift                    # mirrors backend `Device` / `DeviceState` / `Capability`
│   ├── Scene.swift
│   ├── VoiceStatus.swift
│   └── Notification.swift
├── Views/
│   ├── RootView.swift                  # Tab/Split container with Aurora background
│   ├── Dashboard/
│   │   ├── DashboardView.swift
│   │   ├── HeroDeviceCard.swift
│   │   ├── DeviceTile.swift
│   │   ├── LightRow.swift
│   │   └── RoomTabs.swift
│   ├── Devices/DevicesView.swift
│   ├── Routines/RoutinesView.swift
│   ├── Activity/ActivityView.swift
│   ├── News/NewsView.swift             # WKWebView wrapper
│   ├── Settings/SettingsView.swift
│   └── Chrome/
│       ├── JarvisStatusBar.swift
│       └── NotificationsSheet.swift
├── Effects/
│   ├── AuroraBackground.swift          # MTKView + shader
│   ├── SoftAurora.metal                # port of SoftAurora.jsx fragment shader
│   └── MicLevelReader.swift            # AVAudioEngine RMS reader → @Published level
└── Resources/
    ├── Assets.xcassets                 # SF Symbols + brand mark
    └── Info.plist                      # NSMicrophoneUsageDescription, ATS, Bonjour
```

### 9.5 Authentication & Server Flow

1. On launch, read `serverBaseURL` + `authToken` from Keychain.
2. If both exist, call `GET /api/system/health` with the token; on 200 proceed to app shell.
3. If 401, fall back to `LoginView` which posts to `POST /api/auth/login` with `{username, password}` and stores `{token}` in Keychain.
4. If the server address is missing or unreachable, show `ServerSetupView` with manual entry (`http://quantum-home.local:8080`) and Bonjour results.
5. All subsequent REST calls attach `Authorization: Bearer <token>`; WebSocket connects to `ws(s)://<host>/ws?token=<token>`.
6. On any 401, purge Keychain and route back to login.
7. "Sign out" purges Keychain, closes the WebSocket, and clears in-memory state.

### 9.6 Realtime & Voice Integration

- WebSocket events and the app's reaction:
  - `snapshot` → replace rooms/devices in `AppState`.
  - `device.updated` → merge into the matching room/device (same shape as `mergeDevice()` in `main.jsx`).
  - `voice.status` → update `JarvisStatusBar` label (`listening`, `processing`, etc.).
  - `voice.command` → update status bar + append to notifications when `understood == false` (`command_error` / `error`).  When payload contains `navigate` and the value matches a known tab (`Dashboard`, `Devices`, `Routines`, `Activity`, `News`), switch the selected tab.
  - `scene.ran` → append to notifications.
- The iOS app does **not** do wake-word / STT locally; it shows state driven by the Pi's voice pipeline. The Jarvis status bar is a read-only mirror. A future phase can add a "push-to-talk" button that posts transcribed text to `POST /api/voice/command`.

### 9.7 Microphone-Reactive Aurora

- Request mic permission on first app launch with a clear usage string in `Info.plist` ("Reactive background animation and optional voice control").
- `MicLevelReader` uses `AVAudioEngine.inputNode.installTap(onBus: 0, ...)` with a 1024-sample buffer, computes RMS per buffer, smooths with an exponential filter (`smoothed = 0.85·smoothed + 0.15·rms`), and publishes a `@Published var level: Float` in `[0, 1]`.
- `AuroraBackground` hosts an `MTKView`. The fragment shader is a direct port of `SoftAurora.jsx` (keep uniform names identical: `uTime`, `uNoiseFreq`, `uNoiseAmp`, `uBandHeight`, `uBandSpread`, `uColor1`, `uColor2`, etc.). Each frame the renderer updates these uniforms using the base values and the current mic level, with the same gain formulas as the web component:
  - `uNoiseAmp = base · (1 + level · 1.5)`
  - `uNoiseFreq = base · (1 + level · 0.6)`
  - `uBandHeight = base + level · 0.45`
  - `uBandSpread = base · (1 + level · 1.2)`
- If the user denies mic access, the aurora keeps rendering at base values.
- Pause rendering in `scenePhase == .background` to save battery.

### 9.8 Glass UI Guidelines

Match the touchscreen visual language:

- Use `.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))` for cards and `.thinMaterial` for the sidebar / bottom bar. Accent colour `#CBB3FF`, secondary accent `#8FD3FF`.
- Typography: SF Pro; dashboards use `rounded` weight for the big numbers (`HeroDeviceCard.bigNumber`).
- Device-on states keep a purple tint: `LinearGradient` from `#2A2242` to `#1C1C22` at 55% opacity over the aurora.
- All modals use `.presentationDetents([.medium, .large])` with `.presentationBackground(.thinMaterial)`.
- Dark mode only (match the touchscreen kiosk).

### 9.9 News Tab

- Present `WKWebView` configured with:
  - `allowsBackForwardNavigationGestures = true`
  - `configuration.websiteDataStore = .nonPersistent()` to avoid accumulating cookies from third-party news sites.
  - A toolbar with `Back`, `Reload`, `Open in Safari` (using `UIApplication.shared.open`).
- Initial URL: `https://www.worldmonitor.app`. Handle `didFailProvisionalNavigation` with a retry + offline card.
- The voice command `show me latest news` (any of the templates in `home-assistant/config/commands.yaml`) will switch to this tab via the `navigate` event.

### 9.10 Offline & Error Handling

- `NWPathMonitor` drives a `ReachabilityBanner` at the top of the app when the server is unreachable.
- All REST calls go through `APIClient.request(_:)` which centralises: timeouts (5s connect, 15s read), retries for transient errors (2×), 401 handling, and mapping to a `QuantumHomeError` enum (`unauthorized`, `unreachable`, `serverError(String)`).
- The WebSocket client uses exponential backoff reconnect with jitter, capped at 30 s.
- When offline, device toggles fail fast with a toast — no optimistic mutation is committed until the server confirms via `device.updated`.

### 9.11 Delivery Phases

- **iOS‑Phase 0:** Xcode project scaffold, `AppState`, Keychain, login flow against the running Pi, rooms/devices list (read-only), device toggles, health banner.
- **iOS‑Phase 1:** Hero device card with brightness/colour sliders, per-room grid, routines, realtime WebSocket merge of `device.updated`.
- **iOS‑Phase 2:** Jarvis status bar + notifications feed driven by `voice.status` / `voice.command` / `scene.ran`. News tab (`WKWebView`).
- **iOS‑Phase 3:** Aurora background (Metal shader) + `MicLevelReader`. Settings screen (server address, cache clear, sign out). Bonjour discovery.
- **iOS‑Phase 4:** iPad layout with `NavigationSplitView`, iOS Widgets (single-device toggle), and a Siri Shortcut that posts to `POST /api/voice/command`.

### 9.12 Backend Touch-Ups Needed For The iOS App

- Add a Bonjour/mDNS advertisement on the Pi (`avahi-publish-service "Quantum Home" _quantum-home._tcp 8080`, or an `avahi-aliases`-style systemd unit) so `NWBrowser` can auto-discover the server.
- Expose a capability manifest endpoint (e.g. `GET /api/system/manifest`) returning app version, min client version, and feature flags so iOS can refuse to start against an incompatible backend.
- Consider device-scoped push credentials (per-device tokens) instead of the single shared `APP_PASSWORD` once the iOS app ships.
- When the backend starts serving HTTPS (planned post‑LAN phase), add a self-signed certificate trust flow in iOS (pinning or a user-approved certificate).
