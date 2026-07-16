# Ultrahuman Ring AIR

Vokrr reads Ring AIR wellness data through its FastAPI backend. The Qt kiosk never receives the API token, authorization headers, account email, or raw Ultrahuman payload.

## Configure

1. Generate a Personal API token in the Ultrahuman developer portal.
2. Add `UH_TOKEN` to the root `.env` file. Leave `UH_ACCOUNT` empty for a Personal token.
3. If Ultrahuman issued legacy partner credentials, set `UH_ACCOUNT` to the ring account email and enter the supplied data-sharing code in the Ultrahuman app under **Profile > Settings > Partner ID**. The code is not sent with API requests.
4. Rebuild and restart the backend:

   ```bash
   docker compose -f infra/docker-compose.yml up -d --build backend
   ```

Anyone holding the API token can read the associated Ultrahuman data. Keep it out of Git, frontend code, screenshots, logs, and support bundles. Rotate or deactivate it in the Ultrahuman developer portal if exposed.

## Synchronization

The Health screen fetches data when the authenticated kiosk session starts, when the screen opens, every 60 seconds while visible, and on manual refresh. Vokrr prevents overlapping refreshes, retries transient failures with bounded backoff, and keeps a five-minute in-memory cache by default. A stale cache is used only for temporary provider failures and is labeled `CACHED`.

Today uses one daily request. Week uses up to seven sequential daily requests. Ultrahuman epoch requests are validated to a maximum of seven days. Cache contents are process memory only and are deleted when the backend restarts.

## Verify

1. Open Health and confirm the header reports `LATEST` rather than `NOT CONFIGURED` or `SYNC UNAVAILABLE`.
2. Select Today and Week and verify only available metrics render; missing values must show `--` or an unavailable state.
3. Use the refresh control and confirm the last synchronization time changes after Ultrahuman has new data.
4. Check Settings > Ultrahuman Ring for connected and cached status.

The dashboard displays wellness information, not medical diagnoses. Freshness depends on synchronization between Ring AIR, the Ultrahuman app, and Ultrahuman's service.

## Test

```bash
cd backend
. .venv/bin/activate
pytest tests/test_ultrahuman.py
```

To disconnect, remove `UH_TOKEN` and `UH_ACCOUNT` from `.env`, then restart the backend. Restarting also deletes the in-memory health cache. No database migration or persistent health-data cleanup is required.
