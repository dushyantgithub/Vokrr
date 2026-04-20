# Troubleshooting

## Backend Cannot Reach Home Assistant

Check that Home Assistant is listening on the host:

```bash
curl http://localhost:8123/api/
```

Then check the backend environment:

```bash
docker compose -f infra/docker-compose.yml exec backend env | grep HOME_ASSISTANT
```

For this stack, `HOME_ASSISTANT_URL` should normally be `http://host.docker.internal:8123`.

## UI Loads But Devices Are Missing

Check the mapping file:

```bash
cat home-assistant/config/devices.yaml
curl http://localhost:8080/api/rooms
```

The example entity IDs must be replaced with real Home Assistant entity IDs from `/api/ha/entities`.

