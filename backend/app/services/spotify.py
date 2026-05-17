import json
import secrets
import time
from base64 import b64encode
from pathlib import Path
from typing import Any
from urllib.parse import urlencode

import httpx
from fastapi import HTTPException, status

from app.core.config import Settings
from app.domain.models import SpotifyPlaybackResponse


SPOTIFY_ACCOUNTS_BASE = "https://accounts.spotify.com"
SPOTIFY_API_BASE = "https://api.spotify.com/v1"
SPOTIFY_SCOPES = [
    "user-read-currently-playing",
    "user-read-playback-state",
    "user-modify-playback-state",
]


class SpotifyService:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.token_path = Path(settings.spotify_token_path)
        self._oauth_state: str | None = None

    @property
    def configured(self) -> bool:
        return bool(
            self.settings.spotify_app_client_id
            and self.settings.spotify_app_client_secret
            and self.settings.spotify_redirect_uri
        )

    def auth_url(self) -> str:
        if not self.configured:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Spotify app credentials are not configured",
            )

        self._oauth_state = secrets.token_urlsafe(24)
        query = urlencode({
            'client_id': self.settings.spotify_app_client_id,
            'response_type': 'code',
            'redirect_uri': self.settings.spotify_redirect_uri,
            'state': self._oauth_state,
            'scope': ' '.join(SPOTIFY_SCOPES),
        })
        return f"{SPOTIFY_ACCOUNTS_BASE}/authorize?{query}"

    async def handle_callback(self, code: str | None, state: str | None, error: str | None) -> None:
        if error:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=error)
        if not code:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Missing code")
        if self._oauth_state and state != self._oauth_state:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid state")

        payload = {
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": self.settings.spotify_redirect_uri,
        }
        token = await self._token_request(payload)
        self._write_token(token)
        self._oauth_state = None

    async def playback(self) -> SpotifyPlaybackResponse:
        if not self.configured:
            return SpotifyPlaybackResponse(
                configured=False,
                connected=False,
                needs_auth=True,
                detail="Spotify app credentials are not configured",
            )

        access_token = await self._access_token_or_none()
        if not access_token:
            return SpotifyPlaybackResponse(configured=True, connected=False, needs_auth=True)

        try:
            data = await self._api_json("GET", "/me/player", access_token)
        except HTTPException as exc:
            if exc.status_code in {status.HTTP_401_UNAUTHORIZED, status.HTTP_403_FORBIDDEN}:
                return SpotifyPlaybackResponse(
                    configured=True,
                    connected=False,
                    needs_auth=True,
                    detail=str(exc.detail),
                )
            raise

        if not data:
            return SpotifyPlaybackResponse(
                configured=True,
                connected=True,
                is_playing=False,
                title="Open Spotify",
                artist="Start playback on any device",
                detail="No active Spotify playback",
            )

        item = data.get("item") or {}
        artists = ", ".join(artist.get("name", "") for artist in item.get("artists", []) if artist)
        images = ((item.get("album") or {}).get("images") or [])
        device = data.get("device") or {}
        return SpotifyPlaybackResponse(
            configured=True,
            connected=True,
            is_playing=bool(data.get("is_playing")),
            title=item.get("name") or "Spotify",
            artist=artists or (item.get("show") or {}).get("name") or "Unknown artist",
            album_name=(item.get("album") or {}).get("name", ""),
            album_art_url=images[0].get("url", "") if images else "",
            progress_ms=int(data.get("progress_ms") or 0),
            duration_ms=int(item.get("duration_ms") or 45000),
            device_name=device.get("name") or "",
            device_id=device.get("id"),
        )

    async def control(self, action: str) -> None:
        access_token = await self._access_token()
        if action == "play":
            await self._api_empty("PUT", "/me/player/play", access_token)
        elif action == "pause":
            await self._api_empty("PUT", "/me/player/pause", access_token)
        elif action == "next":
            await self._api_empty("POST", "/me/player/next", access_token)
        elif action == "previous":
            await self._api_empty("POST", "/me/player/previous", access_token)
        else:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Unsupported action")

    async def devices(self) -> list[dict[str, Any]]:
        access_token = await self._access_token()
        data = await self._api_json("GET", "/me/player/devices", access_token)
        return list((data or {}).get("devices") or [])

    async def transfer_to_device_named(self, name: str = "Vokrr", play: bool = True) -> dict[str, Any]:
        access_token = await self._access_token()
        devices = await self.devices()
        target = next(
            (device for device in devices if str(device.get("name", "")).lower() == name.lower()),
            None,
        )
        if not target:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Spotify device '{name}' is not available yet",
            )
        await self._api_empty(
            "PUT",
            "/me/player",
            access_token,
            json_body={"device_ids": [target["id"]], "play": play},
        )
        return target

    async def _access_token_or_none(self) -> str | None:
        token = self._read_token()
        if not token:
            return None
        if int(token.get("expires_at", 0)) > int(time.time()) + 30:
            return str(token.get("access_token") or "")
        refresh_token = token.get("refresh_token")
        if not refresh_token:
            return None
        refreshed = await self._token_request(
            {"grant_type": "refresh_token", "refresh_token": refresh_token}
        )
        if "refresh_token" not in refreshed:
            refreshed["refresh_token"] = refresh_token
        self._write_token(refreshed)
        return str(refreshed.get("access_token") or "")

    async def _access_token(self) -> str:
        if not self.configured:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Spotify app credentials are not configured",
            )
        access_token = await self._access_token_or_none()
        if not access_token:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Spotify login required")
        return access_token

    async def _token_request(self, payload: dict[str, str]) -> dict[str, Any]:
        auth = b64encode(
            f"{self.settings.spotify_app_client_id}:{self.settings.spotify_app_client_secret}".encode()
        ).decode()
        async with httpx.AsyncClient(timeout=12) as client:
            response = await client.post(
                f"{SPOTIFY_ACCOUNTS_BASE}/api/token",
                data=payload,
                headers={
                    "Authorization": f"Basic {auth}",
                    "Content-Type": "application/x-www-form-urlencoded",
                },
            )
        if response.status_code >= 400:
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail=f"Spotify token request failed: {response.text}",
            )
        data = response.json()
        data["expires_at"] = int(time.time()) + int(data.get("expires_in", 3600))
        return data

    async def _api_json(self, method: str, path: str, access_token: str) -> dict[str, Any] | None:
        async with httpx.AsyncClient(timeout=8) as client:
            response = await client.request(
                method,
                f"{SPOTIFY_API_BASE}{path}",
                headers={"Authorization": f"Bearer {access_token}"},
            )
        if response.status_code == status.HTTP_204_NO_CONTENT:
            return None
        if response.status_code >= 400:
            raise HTTPException(
                status_code=response.status_code,
                detail=f"Spotify API request failed: {response.text}",
            )
        return response.json()

    async def _api_empty(
        self,
        method: str,
        path: str,
        access_token: str,
        json_body: dict[str, Any] | None = None,
    ) -> None:
        async with httpx.AsyncClient(timeout=8) as client:
            response = await client.request(
                method,
                f"{SPOTIFY_API_BASE}{path}",
                headers={"Authorization": f"Bearer {access_token}"},
                json=json_body,
            )
        if response.status_code not in {status.HTTP_200_OK, status.HTTP_202_ACCEPTED, status.HTTP_204_NO_CONTENT}:
            raise HTTPException(
                status_code=response.status_code,
                detail=f"Spotify API request failed: {response.text}",
            )

    def _read_token(self) -> dict[str, Any] | None:
        try:
            return json.loads(self.token_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return None

    def _write_token(self, token: dict[str, Any]) -> None:
        self.token_path.parent.mkdir(parents=True, exist_ok=True)
        self.token_path.write_text(json.dumps(token, indent=2), encoding="utf-8")
