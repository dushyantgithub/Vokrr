# Quantum Home iOS App

The native iOS client lives in `ios/QuantumHome/`.

## What It Includes

- SwiftUI iPhone app targeting iOS 16+.
- Login flow backed by the public Quantum Home backend over HTTPS.
- Short-lived JWT access tokens plus refresh-token rotation.
- Default server address generated from `IOS_DEFAULT_SERVER_URL`.
- Live room, device, routine, activity, news, and settings views.
- Device state updates through the backend APIs only.
- WebSocket subscription for `snapshot`, `device.updated`, `voice.status`, `voice.command`, and `scene.ran`.

The iOS app should talk only to your backend hostname, for example `https://api.vokrr.com`. It should not call Home Assistant directly and it no longer needs Tailscale for normal remote usage.

## Local Build

```bash
python3 scripts/generate_ios_project.py
xcodebuild -project ios/QuantumHome/QuantumHome.xcodeproj \
  -scheme QuantumHome \
  -destination 'platform=iOS Simulator,name=iPhone 16e' \
  build
```

## Test On iPhone

1. Open `ios/QuantumHome/QuantumHome.xcodeproj` in Xcode.
2. Select the `QuantumHome` scheme.
3. Choose your iPhone as the run destination.
4. Set your Apple Developer Team in `Signing & Capabilities`.
5. In the app login screen, set the server to your public backend URL such as `https://api.vokrr.com`.
6. Sign in with the bootstrap admin account you configured on the Raspberry Pi.
7. Verify:
   - Dashboard loads rooms and devices over mobile data or a different Wi-Fi network.
   - Device toggles work.
   - Room power actions work.
   - Routines execute.
   - Realtime updates reconnect after backgrounding the app.
   - Signing out clears the local session.

## Security Model

1. Home Assistant stays private on the Raspberry Pi LAN and is never exposed publicly.
2. The backend is the only internet-facing service.
3. TLS is terminated at the public edge, typically by Cloudflare Tunnel for CGNAT-safe deployments.
4. Backend auth is database-backed with per-user credentials, JWT access tokens, refresh-token rotation, and activity logging.
5. New user registration is disabled by default and can be enabled temporarily with a registration code.
