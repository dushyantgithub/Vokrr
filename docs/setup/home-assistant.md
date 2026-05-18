# Home Assistant Setup

Vokrr uses Home Assistant as the integration and device engine. Vokrr clients talk to the Vokrr backend; the backend talks to Home Assistant through REST and WebSocket APIs.

## Start Home Assistant

```bash
docker compose -f infra/docker-compose.yml up -d homeassistant
docker compose -f infra/docker-compose.yml logs -f --tail=100 homeassistant
```

Open:

```text
http://vokrr.local:8123
```

Create the Home Assistant admin account and add integrations.

## Long-Lived Access Token

1. Open your Home Assistant user profile.
2. Create a long-lived access token.
3. Put it in `.env` and `scripts/.env`:

```bash
HOME_ASSISTANT_URL=http://localhost:8123
HOME_ASSISTANT_TOKEN=<token>
```

The Compose stack uses host networking, so `localhost:8123` is valid from the backend and voice containers.

## Areas and Devices

Recommended setup:

1. Create rooms/areas in Home Assistant.
2. Assign devices to areas.
3. Confirm entity names and states are correct in Home Assistant.
4. Start/restart Vokrr backend or call `/api/devices/refresh`.

Vokrr stores imported devices in `backend/data/onboarding.db` and merges them with static YAML from `home-assistant/config/devices.yaml`.

## Tuya Devices

Pair Tuya devices through Home Assistant. Vokrr does not currently use direct Tuya cloud APIs.

## Discovery API

After logging in to Vokrr:

```bash
TOKEN=$(curl -sS http://localhost:8080/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"change-this-admin-password"}' \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])')

curl -sS http://localhost:8080/api/ha/entities \
  -H "Authorization: Bearer ${TOKEN}" \
  | python3 -m json.tool
```

## Health Checks

```bash
curl -H "Authorization: Bearer ${HOME_ASSISTANT_TOKEN}" http://localhost:8123/api/
curl -sS http://localhost:8080/api/system/health | python3 -m json.tool
```
