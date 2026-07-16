from datetime import date
from types import SimpleNamespace

import httpx
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.api.routes import router
from app.core.config import Settings, get_settings
from app.main_state import get_app_state
from app.services.auth import AuthService
from app.services.ultrahuman import (
    MAX_RANGE_SECONDS,
    UltrahumanClient,
    UltrahumanError,
    UltrahumanService,
    normalize_daily_metrics,
)


def envelope(metric_data=None, timezone_name="Asia/Kolkata"):
    return {
        "data": {
            "latest_time_zone": timezone_name,
            "metric_data": metric_data or [],
        },
        "error": None,
        "status": 200,
    }


def test_query_validation() -> None:
    assert UltrahumanClient.build_query(date_value="2026-07-16") == {"date": "2026-07-16"}
    assert UltrahumanClient.build_query(start_epoch=100, end_epoch=200) == {
        "start_epoch": 100,
        "end_epoch": 200,
    }
    with pytest.raises(ValueError):
        UltrahumanClient.build_query(date_value="2026-07-16", start_epoch=100, end_epoch=200)
    with pytest.raises(ValueError):
        UltrahumanClient.build_query(start_epoch=100, end_epoch=100 + MAX_RANGE_SECONDS + 1)
    with pytest.raises(ValueError):
        UltrahumanClient.build_query(date_value="16-07-2026")


@pytest.mark.asyncio
async def test_authorization_header_and_personal_query() -> None:
    observed = {}

    def handler(request: httpx.Request) -> httpx.Response:
        observed["authorization"] = request.headers.get("Authorization")
        observed["params"] = dict(request.url.params)
        return httpx.Response(200, json=envelope())

    client = UltrahumanClient(
        "sanitized-test-token",
        max_retries=0,
        transport=httpx.MockTransport(handler),
    )
    await client.fetch_day(date(2026, 7, 16))

    assert observed == {
        "authorization": "sanitized-test-token",
        "params": {"date": "2026-07-16"},
    }


@pytest.mark.asyncio
async def test_partner_query_adds_account_without_access_code() -> None:
    observed = {}

    def handler(request: httpx.Request) -> httpx.Response:
        observed.update(request.url.params)
        return httpx.Response(200, json=envelope())

    client = UltrahumanClient(
        "sanitized-test-token",
        "owner@example.test",
        max_retries=0,
        transport=httpx.MockTransport(handler),
    )
    await client.fetch_day(date(2026, 7, 16))

    assert observed == {"date": "2026-07-16", "email": "owner@example.test"}


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("status_code", "code"),
    [
        (400, "invalid_request"),
        (401, "unauthorized"),
        (403, "unauthorized"),
        (404, "no_data"),
        (429, "rate_limited"),
        (500, "service_unavailable"),
    ],
)
async def test_http_errors_are_safe(status_code: int, code: str) -> None:
    token = "token-that-must-never-appear"
    transport = httpx.MockTransport(
        lambda request: httpx.Response(status_code, json={"error": f"bad {token}"})
    )
    client = UltrahumanClient(token, max_retries=0, transport=transport)

    with pytest.raises(UltrahumanError) as exc_info:
        await client.fetch_day(date(2026, 7, 16))

    assert exc_info.value.code == code
    assert token not in str(exc_info.value)


@pytest.mark.asyncio
async def test_server_error_retries_then_succeeds(monkeypatch: pytest.MonkeyPatch) -> None:
    requests = 0

    def handler(request: httpx.Request) -> httpx.Response:
        nonlocal requests
        requests += 1
        if requests == 1:
            return httpx.Response(503, json={"error": "unavailable"})
        return httpx.Response(200, json=envelope())

    async def no_sleep(_seconds):
        return None

    monkeypatch.setattr("app.services.ultrahuman.asyncio.sleep", no_sleep)
    client = UltrahumanClient(
        "sanitized-test-token", max_retries=1, transport=httpx.MockTransport(handler)
    )

    assert await client.fetch_day(date(2026, 7, 16)) == envelope()
    assert requests == 2


@pytest.mark.asyncio
async def test_timeout_is_normalized() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        raise httpx.ReadTimeout("private transport detail", request=request)

    client = UltrahumanClient(
        "sanitized-test-token", max_retries=0, transport=httpx.MockTransport(handler)
    )
    with pytest.raises(UltrahumanError) as exc_info:
        await client.fetch_day(date(2026, 7, 16))
    assert exc_info.value.code == "timeout"
    assert "private transport detail" not in str(exc_info.value)


def test_normalization_deduplicates_and_ignores_malformed_samples() -> None:
    payload = envelope(
        [
            {
                "type": "hr",
                "object": {
                    "values": [
                        {"timestamp": 1_752_665_400, "value": 62},
                        {"timestamp": 1_752_665_400, "value": 64},
                        {"timestamp": "invalid", "value": 70},
                        {"timestamp": 1_752_665_700, "value": None},
                    ]
                },
            },
            {
                "type": "hrv",
                "object": {"avg": 58, "values": []},
            },
            {
                "type": "steps",
                "object": {"total": 4321, "values": []},
            },
        ]
    )

    result, timezone_name = normalize_daily_metrics(payload, date(2025, 7, 16))

    assert timezone_name == "Asia/Kolkata"
    assert len(result.series["hr"]) == 1
    assert result.series["hr"][0].value == 64
    assert result.series["hr"][0].local_time.endswith("+05:30")
    assert result.latest_heart_rate.value == 64
    assert result.average_hrv.value == 58
    assert result.activity.steps.value == 4321
    assert result.rejected_samples == 2


def test_sleep_stage_aggregation_and_optional_fields() -> None:
    payload = envelope(
        [
            {
                "type": "Sleep",
                "object": {
                    "bedtime_start": 1_752_637_400,
                    "bedtime_end": 1_752_666_200,
                    "sleep_score": {"score": 88},
                    "total_sleep": {"seconds": 25_200},
                    "time_in_bed": {"minutes": 480},
                    "deep_sleep": {"seconds": 5_400},
                    "light_sleep": {"seconds": 13_800},
                    "rem_sleep": {"seconds": 6_000},
                    "sleep_efficiency": {"percentage": 87.5},
                    "sleep_graph": {
                        "data": [
                            {
                                "start": 1_752_637_400,
                                "end": 1_752_641_000,
                                "type": "light_sleep",
                            }
                        ]
                    },
                },
            }
        ]
    )

    result, _ = normalize_daily_metrics(payload, date(2025, 7, 16))

    assert result.sleep.total_sleep_seconds == 25_200
    assert result.sleep.time_in_bed_seconds == 28_800
    assert {stage.stage: stage.seconds for stage in result.sleep.stages} == {
        "deep": 5_400,
        "light": 13_800,
        "rem": 6_000,
        "awake": 3_600,
    }
    assert result.sleep.timeline[0].stage == "light"
    assert result.sleep.tosses_and_turns is None


def test_previous_period_percentage_change() -> None:
    first, _ = normalize_daily_metrics(
        envelope([{"type": "steps", "object": {"total": 4000, "values": []}}]),
        date(2025, 7, 15),
    )
    second, _ = normalize_daily_metrics(
        envelope([{"type": "steps", "object": {"total": 5000, "values": []}}]),
        date(2025, 7, 16),
    )

    UltrahumanService._apply_previous_changes([first, second])

    assert second.activity.steps.change_from_previous == 25


@pytest.mark.asyncio
async def test_transient_failure_uses_cached_dashboard() -> None:
    class StubClient:
        source_api = "personal"

        def __init__(self):
            self.fail = False

        async def fetch_day(self, _day):
            if self.fail:
                raise UltrahumanError("timeout", "Ultrahuman timed out", transient=True)
            return envelope(
                [{"type": "hr", "object": {"values": [{"timestamp": 1_752_665_400, "value": 62}]}}]
            )

    client = StubClient()
    service = UltrahumanService(client, configured=True)
    first = await service.dashboard(force=True)
    client.fail = True
    fallback = await service.dashboard(force=True)

    assert first.sync.connected is True
    assert fallback.current == first.current
    assert fallback.sync.cached is True
    assert fallback.sync.stale is True


def test_health_route_requires_authentication(tmp_path) -> None:
    settings = Settings(
        auth_database_path=str(tmp_path / "auth.db"),
        onboarding_database_path=str(tmp_path / "onboarding.db"),
        app_bootstrap_admin_username="owner",
        app_bootstrap_admin_password="secure-password",
        app_auth_secret="secure-signing-secret",
    )
    auth = AuthService(settings)
    auth.ensure_bootstrap_admin()
    app = FastAPI()
    app.include_router(router)
    app.dependency_overrides[get_settings] = lambda: settings

    response = TestClient(app).get("/api/health/dashboard")

    assert response.status_code == 401


def test_health_route_rejects_non_owner_users(tmp_path) -> None:
    settings = Settings(
        auth_database_path=str(tmp_path / "auth.db"),
        onboarding_database_path=str(tmp_path / "onboarding.db"),
        app_bootstrap_admin_username="owner",
        app_bootstrap_admin_password="secure-password",
        app_auth_secret="secure-signing-secret",
    )
    auth = AuthService(settings)
    auth.ensure_bootstrap_admin()
    owner_session = auth.login("owner", "secure-password", request=None)
    owner = auth.verify_access_token(owner_session["access_token"])
    auth.create_user("viewer", "viewer-password", False, owner, request=None)
    viewer_session = auth.login("viewer", "viewer-password", request=None)
    app = FastAPI()
    app.include_router(router)
    app.dependency_overrides[get_settings] = lambda: settings

    response = TestClient(app).get(
        "/api/health/dashboard",
        headers={"Authorization": f"Bearer {viewer_session['access_token']}"},
    )

    assert response.status_code == 403


def test_health_route_returns_only_normalized_data(tmp_path) -> None:
    settings = Settings(
        auth_database_path=str(tmp_path / "auth.db"),
        onboarding_database_path=str(tmp_path / "onboarding.db"),
        app_bootstrap_admin_username="owner",
        app_bootstrap_admin_password="secure-password",
        app_auth_secret="secure-signing-secret",
    )
    auth = AuthService(settings)
    auth.ensure_bootstrap_admin()
    session = auth.login("owner", "secure-password", request=None)

    async def dashboard(_days, force=False):
        _ = force
        service = UltrahumanService(UltrahumanClient(""), configured=False)
        return await service.dashboard(_days)

    app = FastAPI()
    app.include_router(router)
    app.dependency_overrides[get_settings] = lambda: settings
    app.dependency_overrides[get_app_state] = lambda: SimpleNamespace(
        ultrahuman_service=SimpleNamespace(dashboard=dashboard)
    )
    response = TestClient(app).get(
        "/api/health/dashboard", headers={"Authorization": f"Bearer {session['access_token']}"}
    )

    assert response.status_code == 200
    assert response.headers["cache-control"] == "private, no-store"
    assert session["access_token"] not in response.text
