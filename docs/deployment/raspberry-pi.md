# Raspberry Pi Deployment

## Environment Files

```bash
cp .env.example .env
```

Edit `.env` and set the Home Assistant long-lived token plus the Quantum Home app login values:

```bash
HOME_ASSISTANT_TOKEN=your-home-assistant-token
APP_USERNAME=admin
APP_PASSWORD=replace-this
APP_AUTH_SECRET=replace-with-a-long-random-string
```

## Start Services

```bash
docker compose -f infra/docker-compose.yml up -d --build
docker compose -f infra/docker-compose.yml logs -f --tail=100
```

The local app endpoints are:

- `http://quantum-home.local:3000` for the touchscreen/web UI.
- `http://quantum-home.local:8080` for authenticated backend API clients, including the planned iOS app.
- `http://quantum-home.local:8123` for Home Assistant admin/setup.

## Kiosk Autostart

Install the systemd unit after Chromium and X are installed by Phase 0:

```bash
sudo cp infra/systemd/quantum-home-kiosk.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable quantum-home-kiosk.service
sudo systemctl start quantum-home-kiosk.service
```
