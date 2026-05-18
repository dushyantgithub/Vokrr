# Cloudflare Tunnel Deployment

Cloudflare Tunnel is the recommended remote-access path, especially on CGNAT connections. Expose only the Vokrr backend. Do not expose Home Assistant directly.

## Target Topology

| Item | Value |
| --- | --- |
| Public API hostname | `https://api.vokrr.com` |
| Local backend origin | `http://127.0.0.1:8080` |
| Tunnel service | `cloudflared` Docker service under the `cloudflare` profile |
| Home Assistant | Private on the Raspberry Pi/LAN |

## Configure Environment

Set in `.env` and `scripts/.env`:

```bash
BACKEND_CORS_ORIGINS=https://api.vokrr.com
IOS_DEFAULT_SERVER_URL=https://api.vokrr.com
CLOUDFLARE_TUNNEL_TOKEN=<token-from-cloudflare>
TUNNEL_TOKEN=<same-token-if-required-by-image>
```

## Create the Tunnel

In Cloudflare Zero Trust:

1. Open `Networks` -> `Tunnels`.
2. Create a `Cloudflared` tunnel named `vokrr`.
3. Add a public hostname:
   - Hostname: `api`
   - Domain: `vokrr.com`
   - Service type: `HTTP`
   - URL: `http://127.0.0.1:8080`
4. Copy the tunnel token into the env files.

## Start

```bash
docker compose -f infra/docker-compose.yml --profile cloudflare up -d cloudflared
docker compose -f infra/docker-compose.yml --profile cloudflare logs -f --tail=100 cloudflared
```

The production `vokrr-stack.service` already starts the Compose stack with `--profile cloudflare`.

## Verify

From outside the LAN:

```bash
curl -sS https://api.vokrr.com/api/system/health | python3 -m json.tool
```

Expected shape:

```json
{
  "ok": true,
  "home_assistant": {
    "ok": true
  }
}
```

## Security Notes

- Keep router port forwarding disabled unless there is a separate reason.
- Keep Home Assistant private.
- Disable registration by default: `APP_REGISTRATION_ENABLED=false`.
- Rotate `CLOUDFLARE_TUNNEL_TOKEN` if exposed.
- Use HTTPS backend URL in generated iOS builds.
