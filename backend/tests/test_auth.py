from pathlib import Path

import pytest
from fastapi import HTTPException

from app.core.config import Settings
from app.services.auth import AuthService


def build_settings(tmp_path: Path) -> Settings:
    return Settings(
        auth_database_path=str(tmp_path / "auth.db"),
        app_bootstrap_admin_username="owner",
        app_bootstrap_admin_password="very-secure-bootstrap",
        app_auth_secret="super-secret-signing-key",
        access_token_ttl_seconds=60,
        refresh_token_ttl_seconds=3600,
        app_registration_enabled=True,
        app_registration_code="invite-code",
    )


def test_bootstrap_admin_is_created_once(tmp_path: Path) -> None:
    service = AuthService(build_settings(tmp_path))

    service.ensure_bootstrap_admin()
    service.ensure_bootstrap_admin()

    owner = service.repo.get_user_by_username("owner")
    assert owner is not None
    assert service.repo.count_users() == 1


def test_bootstrap_admin_password_is_updated_from_env(tmp_path: Path) -> None:
    settings = build_settings(tmp_path)
    service = AuthService(settings)
    service.ensure_bootstrap_admin()

    session = service.login("owner", "very-secure-bootstrap", request=None)
    user = service.verify_access_token(session["access_token"])

    settings.app_bootstrap_admin_password = "even-more-secure-password"
    service.ensure_bootstrap_admin()

    with pytest.raises(HTTPException) as exc_info:
        service.refresh_session(session["refresh_token"], request=None)
    assert exc_info.value.status_code == 401

    updated_session = service.login("owner", "even-more-secure-password", request=None)
    assert service.verify_access_token(updated_session["access_token"]).username == user.username


def test_login_and_refresh_issue_rotated_tokens(tmp_path: Path) -> None:
    service = AuthService(build_settings(tmp_path))
    service.ensure_bootstrap_admin()

    session = service.login("owner", "very-secure-bootstrap", request=None)
    user = service.verify_access_token(session["access_token"])
    refreshed = service.refresh_session(session["refresh_token"], request=None)

    assert user.username == "owner"
    assert refreshed["access_token"] != session["access_token"]
    assert refreshed["refresh_token"] != session["refresh_token"]
    assert service.repo.get_refresh_token(session["refresh_token"])["revoked_at"] is not None


def test_register_requires_valid_registration_code(tmp_path: Path) -> None:
    service = AuthService(build_settings(tmp_path))
    service.ensure_bootstrap_admin()

    with pytest.raises(HTTPException) as exc_info:
        service.register_user("guest", "very-secure-password", "wrong-code", request=None)

    assert exc_info.value.status_code == 403

    guest = service.register_user("guest", "very-secure-password", "invite-code", request=None)
    assert guest.username == "guest"
    assert service.repo.get_user_by_username("guest") is not None


def test_recent_activity_contains_auth_events(tmp_path: Path) -> None:
    service = AuthService(build_settings(tmp_path))
    service.ensure_bootstrap_admin()

    session = service.login("owner", "very-secure-bootstrap", request=None)
    actor = service.verify_access_token(session["access_token"])
    service.refresh_session(session["refresh_token"], request=None)

    activity = service.recent_activity(actor)

    assert activity
    assert {entry["action"] for entry in activity} >= {"auth.login", "auth.refresh"}
