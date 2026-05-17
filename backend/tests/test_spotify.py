from pathlib import Path

import pytest

from app.core.config import Settings
from app.services.spotify import SPOTIFY_SCOPES, SpotifyService


def build_settings(tmp_path: Path) -> Settings:
    return Settings(
        spotify_app_name="Vokrr",
        spotify_app_client_id="client-id",
        spotify_app_client_secret="client-secret",
        spotify_redirect_uri="http://127.0.0.1:8080/api/spotify/callback",
        spotify_token_path=str(tmp_path / "spotify_tokens.json"),
    )


def test_auth_url_contains_required_spotify_authorization_fields(tmp_path: Path) -> None:
    service = SpotifyService(build_settings(tmp_path))

    auth_url = service.auth_url()

    assert auth_url.startswith("https://accounts.spotify.com/authorize?")
    assert "client_id=client-id" in auth_url
    assert "response_type=code" in auth_url
    assert "redirect_uri=http%3A%2F%2F127.0.0.1%3A8080%2Fapi%2Fspotify%2Fcallback" in auth_url
    for scope in SPOTIFY_SCOPES:
        assert scope in auth_url


@pytest.mark.asyncio
async def test_callback_exchanges_code_and_persists_token(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    service = SpotifyService(build_settings(tmp_path))
    service.auth_url()
    state = service._oauth_state

    async def fake_token_request(payload):
        assert payload["grant_type"] == "authorization_code"
        assert payload["code"] == "spotify-code"
        return {
            "access_token": "access-token",
            "refresh_token": "refresh-token",
            "expires_in": 3600,
            "expires_at": 1234567890,
        }

    monkeypatch.setattr(service, "_token_request", fake_token_request)

    await service.handle_callback(code="spotify-code", state=state, error=None)

    assert service.token_path.exists()
    assert "access-token" in service.token_path.read_text(encoding="utf-8")


@pytest.mark.asyncio
async def test_playback_maps_current_spotify_track(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    service = SpotifyService(build_settings(tmp_path))

    async def fake_access_token_or_none():
        return "access-token"

    async def fake_api_json(method, path, access_token):
        assert (method, path, access_token) == ("GET", "/me/player", "access-token")
        return {
            "is_playing": True,
            "progress_ms": 12000,
            "device": {"id": "device-1", "name": "Living Room"},
            "item": {
                "name": "Glow",
                "duration_ms": 45000,
                "artists": [{"name": "Echo"}],
                "album": {"images": [{"url": "https://example.test/cover.jpg"}]},
            },
        }

    monkeypatch.setattr(service, "_access_token_or_none", fake_access_token_or_none)
    monkeypatch.setattr(service, "_api_json", fake_api_json)

    playback = await service.playback()

    assert playback.connected is True
    assert playback.is_playing is True
    assert playback.title == "Glow"
    assert playback.artist == "Echo"
    assert playback.progress_ms == 12000
    assert playback.duration_ms == 45000
    assert playback.device_name == "Living Room"
