# Quantum Home iOS App

The native iOS client lives in `ios/QuantumHome/`.

## What It Includes

- SwiftUI iPhone app targeting iOS 16+.
- Login-first flow using the backend `POST /api/auth/login` endpoint.
- Default server address generated from `IOS_DEFAULT_SERVER_URL` in the repo `.env`.
- Live room, device, routine, activity, news, and settings views.
- Device state updates through the real backend APIs.
- Room-level power updates through `POST /api/rooms/{id}/set`.
- WebSocket subscription for `snapshot`, `device.updated`, `voice.status`, `voice.command`, and `scene.ran`.

## Local Build

```bash
python3 scripts/generate_ios_project.py
xcodebuild -project ios/QuantumHome/QuantumHome.xcodeproj \
  -scheme QuantumHome \
  -destination 'platform=iOS Simulator,name=iPhone 16e' \
  build
```

## Test On iPhone 13

1. Open `ios/QuantumHome/QuantumHome.xcodeproj` in Xcode 26 or newer.
2. Select the `QuantumHome` scheme.
3. Connect your iPhone 13 over USB and trust the Mac if prompted.
4. In Xcode, choose your iPhone 13 as the run destination.
5. Open target settings and set your Apple Developer Team under `Signing & Capabilities`.
6. Keep the bundle identifier as-is or change it if your team requires a unique identifier.
7. Confirm the server field in the login screen matches `IOS_DEFAULT_SERVER_URL` from your `.env`.
8. Sign in with:
   - Username: `admin`
   - Password: `admin`
9. Verify:
   - Dashboard loads live rooms and devices.
   - Device tiles open details and can toggle state.
   - Room cards can power a whole room on or off.
   - Routines execute from the backend.
   - Activity reflects backend and WebSocket status.
   - News loads inside the app.

## Any-Network Plan

This is the follow-on plan once you want access from outside your current private network setup:

1. Put the backend behind a public reverse proxy such as Caddy, Nginx, or Traefik on the Raspberry Pi or a fronting host.
2. Serve the backend over HTTPS with a real certificate from Let’s Encrypt.
3. Expose only the backend, not Home Assistant directly, and keep Home Assistant private on the Pi.
4. Move from a single shared password to per-user accounts or at least per-device tokens with revocation.
5. Add request rate limiting and audit logging on login and control endpoints.
6. Add a small `/api/system/manifest` endpoint for client-version compatibility checks.
7. Add DNS such as `api.quantum-home.yourdomain.com` and switch the iOS default server URL to that hostname.
8. Optional hardening:
   - mTLS or signed device enrollment for trusted clients.
   - Push notifications for important home events.
   - Background refresh for stale state detection.
