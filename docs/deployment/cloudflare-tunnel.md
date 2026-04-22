# Cloudflare Tunnel Deployment

Use this when the Raspberry Pi sits behind CGNAT or when you do not want to open inbound ports on the router. This is the recommended public-access setup for `vokrr.com`.

## Target Topology

- Public API hostname: `https://api.vokrr.com`
- Tunnel client: `cloudflared` running on the Raspberry Pi
- Local backend origin: `http://127.0.0.1:8080`
- Home Assistant remains private on the Pi and is never exposed directly

## 1. Prepare Env

Ensure both `.env` and `scripts/.env` contain:

```bash
BACKEND_CORS_ORIGINS=...,https://api.vokrr.com
IOS_DEFAULT_SERVER_URL=https://api.vokrr.com
CLOUDFLARE_TUNNEL_TOKEN=
```

Do not put Home Assistant on a public hostname.

## 2. Create The Tunnel In Cloudflare

In the Cloudflare Zero Trust dashboard:

1. Go to `Networks` -> `Tunnels`.
2. Create a new `Cloudflared` tunnel named `quantum-home`.
3. Add a public hostname:
   - Hostname: `api`
   - Domain: `vokrr.com`
   - Service type: `HTTP`
   - URL: `http://127.0.0.1:8080`
4. Copy the generated tunnel token.

Paste that token into:

```bash
CLOUDFLARE_TUNNEL_TOKEN=your-token-from-cloudflare
```

in both `.env` and `scripts/.env`.

## 3. Start The Tunnel Container

```bash
docker compose -f infra/docker-compose.yml --profile cloudflare up -d cloudflared
docker compose -f infra/docker-compose.yml --profile cloudflare logs -f --tail=100 cloudflared
```

The `cloudflared` service runs in host networking so the tunnel can reach the backend on `127.0.0.1:8080`.

## 4. Verify Public Access

From a device outside your home network:

```bash
curl https://api.vokrr.com/api/system/health
```

Expected response:

```json
{"ok":true,"home_assistant":{"ok":true,"response":{"message":"API running."}}}
```

## 5. Update The iOS App

Regenerate the Xcode project after changing `IOS_DEFAULT_SERVER_URL`:

```bash
python3 scripts/generate_ios_project.py
```

The app should use:

```text
https://api.vokrr.com
```

as the backend base URL.

## 6. Security Notes

- Leave router port forwarding for `80` and `443` disabled.
- Keep Home Assistant bound to the local network only.
- Expose only the backend through the tunnel.
- Keep `APP_REGISTRATION_ENABLED=false` except during intentional onboarding.
- Rotate the Cloudflare tunnel token if it is ever copied into logs or chats.
