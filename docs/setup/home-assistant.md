# Home Assistant Setup

Vokrr uses Home Assistant only as the integration and device engine. The custom UI and voice stack talk to the local backend, and the backend talks to Home Assistant APIs.

## First Start

```bash
docker compose -f infra/docker-compose.yml up -d homeassistant
```

Open `http://vokrr.local:8123`, create the initial admin account, then add device integrations from the Home Assistant UI.

## Long-Lived Access Token

1. In Home Assistant, open your user profile.
2. Create a long-lived access token.
3. Put the token in `infra/env/backend.env`:

```bash
HOME_ASSISTANT_TOKEN=your-token
HOME_ASSISTANT_URL=http://localhost:8123
```

The Compose stack runs Home Assistant and the backend with host networking so LAN discovery works and the backend reaches Home Assistant through `localhost:8123`.

## Vokrr App Login

Home Assistant accounts are not used as normal Vokrr app accounts. Set the bootstrap Vokrr admin account in `.env`:

```bash
APP_BOOTSTRAP_ADMIN_USERNAME=admin
APP_BOOTSTRAP_ADMIN_PASSWORD=replace-this-with-a-strong-password
APP_AUTH_SECRET=replace-with-a-long-random-string
```

Touchscreen, web, voice, and iOS clients call `POST /api/auth/login`, then use the returned `access_token` for protected room/device APIs and WebSocket state updates.

## Entity Discovery

After the backend is running:

```bash
curl http://vokrr.local:8080/api/ha/entities
```

Copy entity IDs into `home-assistant/config/devices.yaml`. Keep Vokrr device IDs stable even if the Home Assistant entity ID changes later.

## API Checks

```bash
curl -H "Authorization: Bearer $HOME_ASSISTANT_TOKEN" \
  http://vokrr.local:8123/api/

curl -H "Authorization: Bearer $HOME_ASSISTANT_TOKEN" \
  http://vokrr.local:8123/api/states
```
