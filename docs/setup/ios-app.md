# Vokrr iOS App

The native iOS client lives in `ios/Vokrr/`.

## What It Includes

- SwiftUI iPhone app targeting iOS 16+.
- Login flow backed by the public Vokrr backend over HTTPS.
- Short-lived JWT access tokens plus refresh-token rotation.
- Default server address generated from `IOS_DEFAULT_SERVER_URL`.
- Live room, device, routine, activity, news, and settings views.
- Device state updates through the backend APIs only.
- WebSocket subscription for `snapshot`, `device.updated`, `voice.status`, `voice.command`, and `scene.ran`.

The iOS app should talk only to your backend hostname, for example `https://api.vokrr.com`. It should not call Home Assistant directly and it no longer needs Tailscale for normal remote usage.

## Local Build

```bash
python3 scripts/generate_ios_project.py
xcodebuild -project ios/Vokrr/Vokrr.xcodeproj \
  -scheme Vokrr \
  -destination 'platform=iOS Simulator,name=iPhone 16e' \
  build
```

If you want to install the app on a physical iPhone, do it from Xcode on a Mac:

1. Open `ios/Vokrr/Vokrr.xcodeproj`.
2. Select the `Vokrr` scheme and choose your iPhone as the run destination.
3. Set your Apple Developer Team under `Signing & Capabilities`.
4. If Xcode asks, allow it to create/update the provisioning profile.
5. Connect the iPhone by cable the first time and tap `Trust` on the device if prompted.
6. Press `Run` in Xcode to build and install the app.
7. On the phone, if iOS blocks the app the first time, open `Settings > General > VPN & Device Management`, trust your developer certificate, and launch again.

## Test On iPhone

1. Open `ios/Vokrr/Vokrr.xcodeproj` in Xcode.
2. Select the `Vokrr` scheme.
3. Choose your iPhone as the run destination.
4. Set your Apple Developer Team in `Signing & Capabilities`.
5. In the app login screen, set the server to your public backend URL such as `https://api.vokrr.com`.
6. Sign in with the bootstrap admin account you configured on the Raspberry Pi.
7. Verify:
   - Dashboard loads rooms and devices over mobile data or a different Wi-Fi network.
   - Device toggles work.
   - Room power actions work.
   - Routines execute.
   - Session survives app relaunch and backend restarts without forcing a fresh login.
   - Admin-only Settings actions can create users and trigger a Raspberry Pi restart.
   - Realtime updates reconnect after backgrounding the app.
   - Signing out clears the local session.

## Security Model

1. Home Assistant stays private on the Raspberry Pi LAN and is never exposed publicly.
2. The backend is the only internet-facing service.
3. TLS is terminated at the public edge, typically by Cloudflare Tunnel for CGNAT-safe deployments.
4. Backend auth is database-backed with per-user credentials, JWT access tokens, refresh-token rotation, and activity logging.
5. New user registration is disabled by default and can be enabled temporarily with a registration code.
