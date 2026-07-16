# Environment Variables

`.env.example` is the source template. The standard deployment loads environment from both `.env` and `scripts/.env`; keep them synchronized unless you intentionally want different host/container values.

Security:

- Do not commit `.env`, `scripts/.env`, `backend/data/*.db`, `backend/data/spotify_tokens.json`, or Home Assistant `.storage` secrets.
- Rotate leaked Home Assistant, Cloudflare, Spotify, Picovoice, and NVIDIA tokens.
- Use a long random `APP_AUTH_SECRET`.

## General

| Name | Required | Example | Description |
| --- | --- | --- | --- |
| `TZ` | Recommended | `Europe/London` | Time zone passed to containers. |
| `LOG_LEVEL` | Optional | `INFO` | Used by the voice pipeline CLI logging. |

## Backend

| Name | Required | Example | Description |
| --- | --- | --- | --- |
| `APP_NAME` | Optional | `Vokrr` | Backend app name setting. |
| `BACKEND_HOST` | Optional | `0.0.0.0` | Uvicorn bind host when running directly. |
| `BACKEND_PORT` | Optional | `8080` | Uvicorn bind port when running directly. |
| `BACKEND_URL` | Optional | `http://localhost:8080` | Used by `scripts/health_check.sh`. |
| `BACKEND_CORS_ORIGINS` | Optional | `https://api.vokrr.com` | Comma-separated CORS origins. |
| `DEVICE_CONFIG_PATH` | Required in container | `/app/config/devices.yaml` | Static room/device/scene YAML path. |
| `COMMAND_CONFIG_PATH` | Required in container | `/app/config/commands.yaml` | Legacy voice command YAML path. |
| `AUTH_DATABASE_PATH` | Required | `/app/data/auth.db` | SQLite auth/session/activity database. |
| `ONBOARDING_DATABASE_PATH` | Required | `/app/data/onboarding.db` | SQLite imported-device database. |
| `APP_BOOTSTRAP_ADMIN_USERNAME` | Required | `admin` | Bootstrap admin username. Legacy alias: `APP_USERNAME`. |
| `APP_BOOTSTRAP_ADMIN_PASSWORD` | Required | `change-me` | Bootstrap admin password. Legacy alias: `APP_PASSWORD`. |
| `APP_USERNAME` | Optional legacy alias | `admin` | Legacy alias read by voice/backend auth paths. Prefer `APP_BOOTSTRAP_ADMIN_USERNAME`. |
| `APP_PASSWORD` | Optional legacy alias | `change-me` | Legacy alias read by voice/backend auth paths. Prefer `APP_BOOTSTRAP_ADMIN_PASSWORD`. |
| `APP_AUTH_SECRET` | Required | `openssl-rand-hex-32` | JWT/signing secret. Treat as highly sensitive. |
| `ACCESS_TOKEN_TTL_SECONDS` | Optional | `900` | JWT access token lifetime. |
| `REFRESH_TOKEN_TTL_SECONDS` | Optional | `2592000` | Refresh token lifetime. |
| `APP_REGISTRATION_ENABLED` | Optional | `false` | Enables public registration endpoint when true. |
| `APP_REGISTRATION_CODE` | Optional | `invite-code` | Required code for registration. |
| `KIOSK_AUTO_LOGIN` | Optional | `true` | Allows localhost `/api/auth/kiosk`. |
| `STATE_SYNC_INTERVAL_SECONDS` | Optional | `5` | Backend periodic HA reconciliation interval. |
| `SYSTEM_RESTART_COMMAND` | Optional | see `.env.example` | Command run by admin restart endpoint. Use carefully. |

## Home Assistant

| Name | Required | Example | Description |
| --- | --- | --- | --- |
| `HOME_ASSISTANT_URL` | Required | `http://localhost:8123` | HA base URL. Host networking makes localhost valid in containers. |
| `HOME_ASSISTANT_TOKEN` | Required for sync/control | `eyJ...` | HA long-lived access token. Sensitive. |

## Ultrahuman Ring AIR

| Name | Required | Example | Description |
| --- | --- | --- | --- |
| `UH_TOKEN` | Required for Ultrahuman | `eyJ...` | Server-only Personal or partner API authorization token. Sensitive. Alias: `ULTRAHUMAN_PERSONAL_API_TOKEN`. |
| `UH_ACCOUNT` | Partner credentials only | `owner@example.com` | Account email required by the legacy partner endpoint. Leave empty for a Personal API token. |
| `ULTRAHUMAN_TIMEOUT_SECONDS` | Optional | `10` | Per-request timeout, bounded from 1 to 30 seconds. |
| `ULTRAHUMAN_MAX_RETRIES` | Optional | `2` | Retry count for timeouts, rate limits, and server failures. Authentication errors are not retried. |
| `ULTRAHUMAN_CACHE_TTL_SECONDS` | Optional | `300` | In-memory daily-metric cache duration, bounded from 30 to 3600 seconds. |

`UH_ACCESS_CODE` is not an API request credential. Enter the data-sharing code in the Ultrahuman app under **Profile > Settings > Partner ID** when using legacy partner access; Vokrr intentionally does not transmit it.

## Network and Wi-Fi

| Name | Required | Example | Description |
| --- | --- | --- | --- |
| `PRIMARY_SSID` | Optional | `HomeWiFi` | Preferred Wi-Fi network. |
| `PRIMARY_SSID_PASSWORD` | Optional | `secret` | Preferred Wi-Fi password. Sensitive. |
| `SECONDARY_SSID` | Optional | `BackupWiFi` | Secondary Wi-Fi network. |
| `SECONDARY_SSID_PASSWORD` | Optional | `secret` | Secondary Wi-Fi password. Sensitive. |
| `WIFI_INTERFACE` | Optional | `wlan0` | Backend network service interface. |
| `VOKRR_WIFI_IFACE` | Optional | `wlan0` | Wi-Fi script interface. |
| `VOKRR_WIFI_SCAN_TIMEOUT_SECONDS` | Optional | `60` | Wi-Fi scan timeout. |
| `VOKRR_WIFI_SCAN_INTERVAL_SECONDS` | Optional | `5` | Wi-Fi scan retry interval. |

## Public Access

| Name | Required | Example | Description |
| --- | --- | --- | --- |
| `IOS_DEFAULT_SERVER_URL` | Optional | `https://api.vokrr.com` | Generated iOS app default server URL. |
| `CLOUDFLARE_TUNNEL_TOKEN` | Optional | `ey...` | Cloudflare tunnel token. Sensitive. |
| `TUNNEL_TOKEN` | Optional | `ey...` | Cloudflared image also recognizes this token. Sensitive. |
| `DUCK_DNS_TOKEN` | Optional | `uuid-token` | Used only by `scripts/update_duckdns.sh`. Sensitive. |
| `DUCK_DNS_DOMAIN` | Optional | `name.duckdns.org` | DuckDNS hostname. |

## Spotify

| Name | Required | Example | Description |
| --- | --- | --- | --- |
| `SPOTIFY_APP_NAME` | Optional | `Vokrr` | App name reference. |
| `SPOTIFY_APP_CLIENT_ID` | Required for Spotify | `abc123` | Spotify OAuth client ID. |
| `SPOTIFY_APP_CLIENT_SECRET` | Required for Spotify | `secret` | Spotify OAuth client secret. Sensitive. |
| `SPOTIFY_REDIRECT_URI` | Required for Spotify | `http://127.0.0.1:8080/api/spotify/callback` | Must match Spotify app settings. |
| `SPOTIFY_TOKEN_PATH` | Optional | `/app/data/spotify_tokens.json` | Stored Spotify OAuth tokens. Sensitive. |

## Kiosk Runtime

| Name | Required | Example | Description |
| --- | --- | --- | --- |
| `VOKRR_API_BASE` | Optional | `http://localhost:8080` | Backend URL passed to Qt app. |
| `VOKRR_QT_BIN` | Optional | `/home/dushyant/apps/Vokrr/qt-frontend/build/vokrr-qt` | Kiosk executable path. |
| `VOKRR_KIOSK_STARTUP_TIMEOUT` | Optional | `180` | Backend wait timeout. |
| `VOKRR_KIOSK_DISPLAY_TIMEOUT` | Optional | `60` | Display session wait timeout. |
| `VOKRR_TOUCH_ROTATION` | Optional | `180` | Applies touch transform for rotated display. |
| `VOKRR_APP_DIR` | Optional | `/home/dushyant/apps/Vokrr` | Script/systemd install root. |
| `PI_USER` | Optional | `homeops` | User added to Docker group by `phase0_setup.sh`. |
| `XDG_RUNTIME_DIR` | Required by systemd kiosk | `/run/user/1000` | Graphical session runtime dir. |
| `WAYLAND_DISPLAY` | Optional | `wayland-0` | Wayland socket name if using Wayland. |
| `DISPLAY` | Optional | `:0` | X11 display used by the kiosk. |
| `XAUTHORITY` | Optional | `/home/dushyant/.Xauthority` | X11 auth file. |
| `QT_QPA_PLATFORM` | Optional | `xcb` | Qt platform plugin selected by service/script. |
| `QT_XCB_NO_XI2` | Optional | `0` | Qt XCB input behavior. |

## Audio

| Name | Required | Example | Description |
| --- | --- | --- | --- |
| `VOKRR_AUDIO_OUTPUT_ENV` | Optional | `backend/data/audio-output.env` | Output env file written by audio selection script. |
| `VOKRR_AUDIO_FALLBACK_DEVICE` | Optional | `plughw:CARD=MAX98357A,DEV=0` | ALSA fallback output. |
| `VOKRR_AUDIO_ALLOW_HDMI` | Optional | `0` | Allow HDMI as an output candidate. |
| `VOICE_OUTPUT_DEVICE` | Optional | `plughw:CARD=Headphones,DEV=0` | ALSA output for voice playback. |
| `VOICE_KEEP_TTS_FILES` | Optional | `0` | Keep generated TTS wav files for debugging. |

## Voice Listener

| Name | Required | Example | Description |
| --- | --- | --- | --- |
| `VOICE_BACKEND_URL` | Required | `http://localhost:8080` | Backend URL used for login/events/fallback commands. |
| `VOICE_WAKE_WORD` | Optional | `Jarvis` | Display label for wake word. |
| `VOICE_LISTENER_ENABLED` | Optional | `1` | Enables microphone listener. |
| `VOICE_INPUT_DEVICE` | Recommended | `USB Device 0x46d:0x825` | Pins the microphone device by name/index. |
| `VOICE_COMMAND_RECORD_SECONDS` | Optional | `10` | Maximum one-shot command recording window. |
| `VOICE_COMMAND_MIN_SECONDS` | Optional | `1.2` | Minimum record time before silence cutoff. |
| `VOICE_COMMAND_SILENCE_SECONDS` | Optional | `1.1` | Silence duration before ending capture. |
| `VOICE_COMMAND_SILENCE_RMS` | Optional | `450` | RMS threshold for voice activity. |
| `VOICE_WAKE_COOLDOWN_SECONDS` | Optional | `2.5` | Rejects wake detections too soon after a turn or playback. |
| `VOICE_POST_SPEECH_COOLDOWN_SECONDS` | Optional | `0.8` | Extra mic pause after local or assistant speech before wake listening resumes. |
| `VOICE_WAKE_MIN_RMS` | Optional | `350` | Minimum recent RMS required to accept a Porcupine wake hit. |
| `VOICE_WAKE_MIN_PEAK_RMS` | Optional | `650` | Minimum recent peak RMS required to accept a Porcupine wake hit. |
| `VOICE_WAKE_RMS_WINDOW_FRAMES` | Optional | `8` | Number of wake-listening frames used for recent energy checks. |
| `VOICE_AUDIO_QUEUE_MAX_CHUNKS` | Optional | `64` | Bounds mic buffering so stale audio cannot build up indefinitely. |
| `VOICE_AUDIO_FRAME_TIMEOUT_SECONDS` | Optional | `5` | Fails a turn if microphone frames stop arriving. |
| `VOICE_FEEDBACK_ENABLED` | Optional | `1` | Enables local wake/error feedback speech. |
| `VOICE_FEEDBACK_WAKE_TEXT` | Optional | `How can I help you sir?` | Wake feedback text. |
| `VOICE_FEEDBACK_MISUNDERSTOOD_TEXT` | Optional | `I am afraid sir, but I didnt get you` | No-command text. |
| `VOICE_TTS_COMMAND` | Optional | `espeak-ng` | Simple feedback TTS command. |
| `VOICE_TTS_RATE` | Optional | `150` | Simple feedback TTS rate. |
| `VOICE_TTS_FALLBACK_ENABLED` | Optional | `1` | Allows command TTS fallback only after the configured TTS API fails. |
| `VOICE_TTS_FALLBACK_TIMEOUT_SECONDS` | Optional | `8` | Timeout for command TTS fallback. |
| `PORCUPINE_API_KEY` | Required for wake word | `...` | Picovoice access key. Sensitive. |
| `PORCUPINE_ACCESS_KEY` | Optional | `...` | Alias fallback for Picovoice key. |
| `PORCUPINE_KEYWORD_PATH` | Required | `/wake-word/Jarvis_en_raspberry-pi_v4_0_0.ppn` | Wake-word model path. |
| `PORCUPINE_SENSITIVITY` | Optional | `0.35` | Porcupine sensitivity. Lower values reduce false wake-ups. |
| `WHISPER_MODEL` | Optional | `base.en` | faster-whisper model. |
| `WHISPER_LANGUAGE` | Optional | `en` | STT language. |
| `WHISPER_DEVICE` | Optional | `cpu` | faster-whisper device. |
| `WHISPER_COMPUTE_TYPE` | Optional | `int8` | faster-whisper compute type. |

## NVIDIA Voice Pipeline

| Name | Required | Example | Description |
| --- | --- | --- | --- |
| `VOICE_NVIDIA_PIPELINE_ENABLED` | Optional | `1` | Enables NVIDIA LLM/TTS pipeline. |
| `NVIDIA_API_KEY` | Required for LLM/TTS | `nvapi-...` | Main NVIDIA API key. Sensitive. |
| `NVIDIA_BUILD_API_KEY` | Optional | `nvapi-...` | Fallback NVIDIA API key used by current deployment. Sensitive. |
| `MAGPIE_API_KEY` | Optional | `nvapi-...` | TTS-specific fallback key. Sensitive. |
| `NVIDIA_LLM_MODEL` | Optional | `meta/llama-4-maverick-17b-128e-instruct` | LLM model name. |
| `NVIDIA_LLM_URL` | Optional | `https://integrate.api.nvidia.com/v1/chat/completions` | NVIDIA chat endpoint. |
| `NVIDIA_LLM_TIMEOUT_SECONDS` | Optional | `20` | LLM request timeout. |
| `NVIDIA_TTS_FUNCTION_ID` | Required for Magpie | `877104f7-e885-42b9-8de8-f6e4c6303969` | Magpie function ID. |
| `NVIDIA_TTS_GRPC_SERVER` | Optional | `grpc.nvcf.nvidia.com:443` | Magpie gRPC server. |
| `NVIDIA_TTS_DEFAULT_VOICE` | Optional | `Magpie-Multilingual.EN-US.Aria` | Voice name. |
| `NVIDIA_TTS_LANGUAGE_CODE` | Optional | `en-US` | TTS language code. |
| `NVIDIA_TTS_SAMPLE_RATE_HZ` | Optional | `44100` | Output wav sample rate. |
| `VOICE_ENTITY_CACHE_SECONDS` | Optional | `8` | HA entity context cache time for voice. |
| `VOICE_ROOM_ALIASES` | Optional | see `.env.example` | Area aliases for voice matching. |

## Legacy Voice Intent Bridge

| Name | Required | Example | Description |
| --- | --- | --- | --- |
| `VOICE_INTENT_PORT` | Optional | `8090` | Legacy bridge port hint. |
| `MODEL_URL` | Optional | Vosk small model URL | Used only by archived `scripts/download_vosk_model.sh`. |
| `MODEL_DIR` | Optional | `voice-pipeline/models` | Used only by archived `scripts/download_vosk_model.sh`. |

## Tuya Values

`TUYA_*` values may exist in local deployments, but the current Vokrr codebase does not read them. Configure Tuya devices in Home Assistant, then import/control those Home Assistant entities in Vokrr.
