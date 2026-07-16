import asyncio
import logging
import math
import random
import time
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from typing import Any
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

import httpx
from pydantic import BaseModel, ConfigDict, ValidationError

from app.domain.health import (
    ActivitySummary,
    DailyHealthSummary,
    HealthDashboardResponse,
    HealthSample,
    HealthSyncMetadata,
    MetricValue,
    RecoverySummary,
    SleepInterval,
    SleepStage,
    SleepSummary,
)

logger = logging.getLogger(__name__)

PERSONAL_METRICS_URL = "https://partner.ultrahuman.com/api/v1/partner/daily_metrics"
PARTNER_METRICS_URL = "https://partner.ultrahuman.com/api/v1/metrics"
MAX_RANGE_SECONDS = 7 * 24 * 60 * 60


class UltrahumanError(Exception):
    def __init__(
        self, code: str, message: str, *, status_code: int | None = None, transient: bool = False
    ):
        super().__init__(message)
        self.code = code
        self.message = message
        self.status_code = status_code
        self.transient = transient


class RawEnvelope(BaseModel):
    model_config = ConfigDict(extra="ignore")

    data: dict[str, Any] | list[Any] | None = None
    error: str | None = None
    status: int | None = None


class UltrahumanClient:
    def __init__(
        self,
        token: str,
        account: str = "",
        *,
        timeout_seconds: float = 10,
        max_retries: int = 2,
        transport: httpx.AsyncBaseTransport | None = None,
    ) -> None:
        self._token = token
        self._account = account
        self._timeout = timeout_seconds
        self._max_retries = max(0, max_retries)
        self._transport = transport

    @property
    def source_api(self) -> str:
        return "partner" if self._account else "personal"

    @staticmethod
    def build_query(
        *,
        date_value: date | str | None = None,
        start_epoch: int | None = None,
        end_epoch: int | None = None,
    ) -> dict[str, str | int]:
        has_date = date_value is not None
        has_epoch = start_epoch is not None or end_epoch is not None
        if has_date == has_epoch:
            raise ValueError("Provide either date or an epoch range")
        if has_date:
            if isinstance(date_value, date):
                parsed = date_value
            else:
                try:
                    parsed = date.fromisoformat(str(date_value))
                except ValueError as exc:
                    raise ValueError("Date must use YYYY-MM-DD") from exc
                if parsed.isoformat() != str(date_value):
                    raise ValueError("Date must use YYYY-MM-DD")
            return {"date": parsed.isoformat()}
        if start_epoch is None or end_epoch is None:
            raise ValueError("Both start_epoch and end_epoch are required")
        if start_epoch < 0 or end_epoch <= start_epoch:
            raise ValueError("Epoch range must be positive and increasing")
        if end_epoch - start_epoch > MAX_RANGE_SECONDS:
            raise ValueError("Epoch range cannot exceed seven days")
        return {"start_epoch": start_epoch, "end_epoch": end_epoch}

    async def fetch_day(self, day: date) -> dict[str, Any]:
        params = self.build_query(date_value=day)
        if self._account:
            params["email"] = self._account
        url = PARTNER_METRICS_URL if self._account else PERSONAL_METRICS_URL
        return await self._request(url, params)

    async def fetch_epoch_range(self, start_epoch: int, end_epoch: int) -> dict[str, Any]:
        params = self.build_query(start_epoch=start_epoch, end_epoch=end_epoch)
        return await self._request(PERSONAL_METRICS_URL, params)

    async def _request(self, url: str, params: dict[str, str | int]) -> dict[str, Any]:
        if not self._token:
            raise UltrahumanError("not_configured", "Ultrahuman is not configured")
        headers = {"Authorization": self._token, "Accept": "application/json"}
        timeout = httpx.Timeout(self._timeout)
        for attempt in range(self._max_retries + 1):
            try:
                async with httpx.AsyncClient(
                    timeout=timeout,
                    transport=self._transport,
                    follow_redirects=True,
                ) as client:
                    response = await client.get(url, params=params, headers=headers)
            except httpx.TimeoutException as exc:
                error = UltrahumanError(
                    "timeout", "Ultrahuman did not respond in time", transient=True
                )
                if attempt < self._max_retries:
                    await self._backoff(attempt)
                    continue
                raise error from exc
            except httpx.NetworkError as exc:
                error = UltrahumanError(
                    "network", "Ultrahuman could not be reached", transient=True
                )
                if attempt < self._max_retries:
                    await self._backoff(attempt)
                    continue
                raise error from exc

            if response.status_code in {429} or response.status_code >= 500:
                error = self._http_error(response.status_code)
                if attempt < self._max_retries:
                    retry_after = self._retry_after(response)
                    if retry_after is not None:
                        await asyncio.sleep(retry_after)
                    else:
                        await self._backoff(attempt)
                    continue
                raise error
            if response.status_code >= 400:
                raise self._http_error(response.status_code)
            try:
                body = response.json()
                envelope = RawEnvelope.model_validate(body)
            except (ValueError, ValidationError) as exc:
                raise UltrahumanError(
                    "malformed_response", "Ultrahuman returned an unreadable response"
                ) from exc
            if envelope.status is not None and envelope.status >= 400:
                raise self._http_error(envelope.status)
            if not isinstance(body, dict):
                raise UltrahumanError(
                    "malformed_response", "Ultrahuman returned an unreadable response"
                )
            return body
        raise UltrahumanError(
            "unavailable", "Ultrahuman is temporarily unavailable", transient=True
        )

    @staticmethod
    async def _backoff(attempt: int) -> None:
        await asyncio.sleep(min(0.35 * (2**attempt) + random.uniform(0, 0.15), 2.0))

    @staticmethod
    def _retry_after(response: httpx.Response) -> float | None:
        raw = response.headers.get("Retry-After")
        if not raw:
            return None
        try:
            return min(max(float(raw), 0), 5)
        except ValueError:
            return None

    @staticmethod
    def _http_error(status_code: int) -> UltrahumanError:
        if status_code == 400:
            return UltrahumanError(
                "invalid_request",
                "Ultrahuman rejected the requested date or account",
                status_code=400,
            )
        if status_code in {401, 403}:
            return UltrahumanError(
                "unauthorized",
                "Ultrahuman credentials are invalid or no longer authorized",
                status_code=status_code,
            )
        if status_code == 404:
            return UltrahumanError(
                "no_data", "No Ultrahuman data is available for this date", status_code=404
            )
        if status_code == 429:
            return UltrahumanError(
                "rate_limited",
                "Ultrahuman is rate limiting synchronization",
                status_code=429,
                transient=True,
            )
        return UltrahumanError(
            "service_unavailable",
            "Ultrahuman is temporarily unavailable",
            status_code=status_code,
            transient=status_code >= 500,
        )


def _number(value: Any) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    number = float(value)
    return number if math.isfinite(number) else None


def _integer(value: Any) -> int | None:
    number = _number(value)
    return int(number) if number is not None else None


def _timestamp(value: Any) -> int | None:
    number = _number(value)
    if number is None or number <= 0:
        return None
    if number > 100_000_000_000:
        number /= 1000
    return int(number)


def _zone(name: Any) -> tuple[ZoneInfo, str]:
    if isinstance(name, str):
        try:
            return ZoneInfo(name), name
        except ZoneInfoNotFoundError:
            pass
    return ZoneInfo("UTC"), "UTC"


def _iso(timestamp: int | None, zone: ZoneInfo) -> str | None:
    if timestamp is None:
        return None
    try:
        return datetime.fromtimestamp(timestamp, tz=timezone.utc).astimezone(zone).isoformat()
    except (OverflowError, OSError, ValueError):
        return None


def _metric(value: Any, unit: str, *, timestamp: str | None = None) -> MetricValue | None:
    number = _number(value)
    return MetricValue(value=number, unit=unit, timestamp=timestamp) if number is not None else None


def _object(entry: dict[str, Any] | None) -> dict[str, Any]:
    if not isinstance(entry, dict):
        return {}
    value = entry.get("object")
    return value if isinstance(value, dict) else {}


def _duration_seconds(value: Any) -> int | None:
    if not isinstance(value, dict):
        return None
    seconds = _integer(value.get("seconds"))
    if seconds is not None:
        return max(seconds, 0)
    minutes = _integer(value.get("minutes"))
    if minutes is not None:
        return max(minutes * 60, 0)
    hours = _integer(value.get("hours"))
    remaining = _integer(value.get("remaining_minutes")) or 0
    if hours is not None:
        return max(hours * 3600 + remaining * 60, 0)
    return None


def _samples(
    metric: str,
    obj: dict[str, Any],
    unit: str,
    zone: ZoneInfo,
) -> tuple[list[HealthSample], int]:
    values = obj.get("values")
    if not isinstance(values, list):
        return [], 0
    deduplicated: dict[int, HealthSample] = {}
    rejected = 0
    for raw in values:
        if not isinstance(raw, dict):
            rejected += 1
            continue
        timestamp = _timestamp(raw.get("timestamp"))
        number = _number(raw.get("value"))
        local_time = _iso(timestamp, zone)
        if timestamp is None or number is None or local_time is None:
            rejected += 1
            continue
        deduplicated[timestamp] = HealthSample(
            timestamp=timestamp,
            local_time=local_time,
            local_date=local_time[:10],
            value=number,
            unit=unit,
            metric=metric,
        )
    return [deduplicated[key] for key in sorted(deduplicated)], rejected


def _downsample(samples: list[HealthSample], maximum: int = 120) -> list[HealthSample]:
    if len(samples) <= maximum:
        return samples
    indices = {round(index * (len(samples) - 1) / (maximum - 1)) for index in range(maximum)}
    return [sample for index, sample in enumerate(samples) if index in indices]


def _sleep_stage_name(value: Any) -> str | None:
    text = str(value or "").strip().lower().replace("_sleep", "").replace(" sleep", "")
    aliases = {"wake": "awake", "awake": "awake", "light": "light", "deep": "deep", "rem": "rem"}
    return aliases.get(text)


def _sleep_summary(obj: dict[str, Any], zone: ZoneInfo) -> SleepSummary:
    score_obj = obj.get("sleep_score") if isinstance(obj.get("sleep_score"), dict) else {}
    total = _duration_seconds(obj.get("total_sleep"))
    in_bed = _duration_seconds(obj.get("time_in_bed"))
    stage_seconds: dict[str, int] = {}
    for name in ("deep", "light", "rem"):
        duration = _duration_seconds(obj.get(f"{name}_sleep"))
        if duration is not None:
            stage_seconds[name] = duration
    if in_bed is not None and total is not None and in_bed >= total:
        stage_seconds["awake"] = in_bed - total
    denominator = sum(stage_seconds.values())
    stages = [
        SleepStage(stage=name, seconds=seconds, percentage=(seconds / denominator * 100))
        for name, seconds in stage_seconds.items()
        if denominator > 0 and seconds > 0
    ]

    timeline: list[SleepInterval] = []
    sleep_graph = obj.get("sleep_graph") if isinstance(obj.get("sleep_graph"), dict) else {}
    graph_data = sleep_graph.get("data") if isinstance(sleep_graph.get("data"), list) else []
    for interval in graph_data:
        if not isinstance(interval, dict):
            continue
        start, end = _timestamp(interval.get("start")), _timestamp(interval.get("end"))
        stage = _sleep_stage_name(interval.get("type"))
        if start is not None and end is not None and end > start and stage is not None:
            timeline.append(SleepInterval(start=start, end=end, stage=stage))

    efficiency_obj = (
        obj.get("sleep_efficiency") if isinstance(obj.get("sleep_efficiency"), dict) else {}
    )
    restorative_obj = (
        obj.get("restorative_sleep") if isinstance(obj.get("restorative_sleep"), dict) else {}
    )
    cycles_obj = (
        obj.get("full_sleep_cycles") if isinstance(obj.get("full_sleep_cycles"), dict) else {}
    )
    tosses_obj = (
        obj.get("tosses_and_turns") if isinstance(obj.get("tosses_and_turns"), dict) else {}
    )
    alertness_obj = (
        obj.get("morning_alertness") if isinstance(obj.get("morning_alertness"), dict) else {}
    )
    return SleepSummary(
        score=_metric(score_obj.get("score"), "score"),
        total_sleep_seconds=total,
        time_in_bed_seconds=in_bed,
        efficiency=_metric(efficiency_obj.get("percentage"), "%"),
        bedtime_start=_iso(_timestamp(obj.get("bedtime_start")), zone),
        bedtime_end=_iso(_timestamp(obj.get("bedtime_end")), zone),
        stages=stages,
        timeline=timeline,
        full_sleep_cycles=_integer(cycles_obj.get("cycles")),
        tosses_and_turns=_integer(tosses_obj.get("count")),
        restorative_sleep=_metric(restorative_obj.get("percentage"), "%"),
        morning_alertness_minutes=_integer(alertness_obj.get("minutes")),
    )


def normalize_daily_metrics(
    payload: dict[str, Any], requested_date: date
) -> tuple[DailyHealthSummary, str]:
    data = payload.get("data")
    if not isinstance(data, dict):
        raise UltrahumanError("malformed_response", "Ultrahuman returned no metric data")
    zone, zone_name = _zone(data.get("latest_time_zone"))
    raw_metrics = data.get("metric_data")
    if not isinstance(raw_metrics, list):
        raise UltrahumanError("malformed_response", "Ultrahuman returned no metric data")
    metrics: dict[str, dict[str, Any]] = {}
    for entry in raw_metrics:
        if isinstance(entry, dict) and isinstance(entry.get("type"), str):
            metrics[entry["type"].lower()] = entry

    units = {"hr": "bpm", "hrv": "ms", "temp": "°C", "motion": "intensity", "glucose": "mg/dL"}
    series: dict[str, list[HealthSample]] = {}
    rejected = 0
    for name in ("hr", "hrv", "temp", "motion", "glucose"):
        samples, invalid = _samples(name, _object(metrics.get(name)), units[name], zone)
        if samples:
            series[name] = _downsample(samples)
        rejected += invalid

    sleep_obj = _object(metrics.get("sleep"))
    sleep = _sleep_summary(sleep_obj, zone)
    for name, graph_name, unit in (
        ("sleep_hr", "hr_graph", "bpm"),
        ("sleep_hrv", "hrv_graph", "ms"),
        ("sleep_temp", "temp_graph", "°C"),
    ):
        graph = sleep_obj.get(graph_name) if isinstance(sleep_obj.get(graph_name), dict) else {}
        samples, invalid = _samples(name, {"values": graph.get("data")}, unit, zone)
        if samples:
            series[name] = _downsample(samples)
        rejected += invalid

    hr = series.get("hr", [])
    temp = series.get("temp", [])
    hrv_obj = _object(metrics.get("hrv"))
    rhr_obj = _object(metrics.get("night_rhr"))
    steps_obj = _object(metrics.get("steps"))
    recovery_obj = _object(metrics.get("recovery"))
    recovery_index_obj = _object(metrics.get("recovery_index"))
    avg_sleep_hrv_obj = _object(metrics.get("avg_sleep_hrv"))
    sleep_rhr_obj = _object(metrics.get("sleep_rhr"))
    movement_obj = _object(metrics.get("movement_index"))
    active_obj = _object(metrics.get("active_minutes"))
    vo2_obj = _object(metrics.get("vo2_max"))
    average_temp_obj = (
        sleep_obj.get("average_body_temperature")
        if isinstance(sleep_obj.get("average_body_temperature"), dict)
        else {}
    )
    deviation_obj = (
        sleep_obj.get("temperature_deviation")
        if isinstance(sleep_obj.get("temperature_deviation"), dict)
        else {}
    )
    spo2_obj = sleep_obj.get("spo2") if isinstance(sleep_obj.get("spo2"), dict) else {}
    restorative = sleep.restorative_sleep

    latest_hr = hr[-1] if hr else None
    latest_temp = temp[-1] if temp else None
    timestamp = latest_hr.local_time if latest_hr else None
    recovery_value = recovery_obj.get("score", recovery_obj.get("value"))
    if recovery_value is None:
        recovery_value = recovery_index_obj.get("value")
    average_hrv = hrv_obj.get("avg")
    if average_hrv is None and series.get("hrv"):
        average_hrv = sum(item.value for item in series["hrv"]) / len(series["hrv"])
    skin_temp_value = average_temp_obj.get("celsius")
    if skin_temp_value is None and latest_temp:
        skin_temp_value = latest_temp.value

    summary = DailyHealthSummary(
        local_date=requested_date.isoformat(),
        latest_heart_rate=_metric(
            latest_hr.value if latest_hr else None, "bpm", timestamp=timestamp
        ),
        average_hrv=_metric(average_hrv, "ms"),
        skin_temperature=_metric(
            skin_temp_value, "°C", timestamp=latest_temp.local_time if latest_temp else None
        ),
        resting_heart_rate=_metric(rhr_obj.get("avg"), "bpm"),
        spo2=_metric(spo2_obj.get("value"), "%"),
        vo2_max=_metric(vo2_obj.get("value"), "mL/kg/min"),
        recovery=RecoverySummary(
            score=_metric(recovery_value, "score"),
            average_sleep_hrv=_metric(avg_sleep_hrv_obj.get("value"), "ms")
            or _metric(average_hrv, "ms"),
            sleep_resting_hr=_metric(sleep_rhr_obj.get("value"), "bpm")
            or _metric(rhr_obj.get("avg"), "bpm"),
            temperature_deviation=_metric(deviation_obj.get("celsius"), "°C"),
            heart_rate_drop=_metric(sleep_obj.get("hr_drop"), "bpm"),
            restorative_sleep=restorative,
        ),
        activity=ActivitySummary(
            steps=_metric(steps_obj.get("total"), "steps"),
            active_minutes=_metric(active_obj.get("value"), "min"),
            movement_index=_metric(movement_obj.get("value"), "score"),
        ),
        sleep=sleep,
        series=series,
        rejected_samples=rejected,
    )
    return summary, zone_name


@dataclass
class _CacheEntry:
    summary: DailyHealthSummary
    timezone_name: str
    stored_at: float
    synchronized_at: datetime


class UltrahumanService:
    def __init__(
        self,
        client: UltrahumanClient,
        *,
        configured: bool,
        cache_ttl_seconds: int = 300,
    ) -> None:
        self.client = client
        self.configured = configured
        self.cache_ttl_seconds = max(cache_ttl_seconds, 30)
        self._cache: dict[str, _CacheEntry] = {}
        self._lock = asyncio.Lock()
        self._last_successful_sync: datetime | None = None

    async def dashboard(self, days: int = 1, *, force: bool = False) -> HealthDashboardResponse:
        if days not in {1, 7}:
            raise ValueError("Health range must be one or seven days")
        if not self.configured:
            return self._empty(days, "not_configured", "Add UH_TOKEN to the backend environment")
        async with self._lock:
            return await self._dashboard_locked(days, force=force)

    async def _dashboard_locked(self, days: int, *, force: bool) -> HealthDashboardResponse:
        today = datetime.now().astimezone().date()
        requested = [today - timedelta(days=offset) for offset in reversed(range(days))]
        summaries: list[DailyHealthSummary] = []
        fallback_used = False
        partial = False
        timezone_name = "UTC"
        failure: UltrahumanError | None = None

        for day in requested:
            key = day.isoformat()
            cached = self._cache.get(key)
            fresh = cached and time.monotonic() - cached.stored_at < self.cache_ttl_seconds
            if fresh and not force:
                summaries.append(cached.summary)
                timezone_name = cached.timezone_name
                continue
            try:
                logger.info("ultrahuman.sync.started date=%s", key)
                payload = await self.client.fetch_day(day)
                summary, timezone_name = normalize_daily_metrics(payload, day)
                now = datetime.now(timezone.utc)
                self._cache[key] = _CacheEntry(summary, timezone_name, time.monotonic(), now)
                self._last_successful_sync = now
                summaries.append(summary)
                logger.info(
                    "ultrahuman.sync.completed date=%s accepted=%s rejected=%s",
                    key,
                    sum(len(values) for values in summary.series.values()),
                    summary.rejected_samples,
                )
            except UltrahumanError as exc:
                failure = exc
                if exc.code == "no_data":
                    partial = True
                    continue
                if cached is not None and exc.transient:
                    summaries.append(cached.summary)
                    timezone_name = cached.timezone_name
                    fallback_used = True
                    partial = True
                    logger.warning("ultrahuman.sync.cached_fallback date=%s code=%s", key, exc.code)
                    continue
                break

        summaries.sort(key=lambda item: item.local_date)
        self._apply_previous_changes(summaries)
        current = summaries[-1] if summaries else None
        latest_source = self._latest_source_time(summaries)
        connected = current is not None and (
            failure is None or failure.transient or failure.code == "no_data"
        )
        message = failure.message if failure and not connected else None
        return HealthDashboardResponse(
            range_days=days,
            current=current,
            daily=summaries,
            sync=HealthSyncMetadata(
                configured=True,
                connected=connected,
                source_api=self.client.source_api,
                timezone=timezone_name,
                last_successful_sync_at=self._last_successful_sync.isoformat()
                if self._last_successful_sync
                else None,
                latest_source_at=latest_source,
                cached=fallback_used,
                stale=fallback_used,
                partial=partial or any(item.rejected_samples for item in summaries),
                error_code=failure.code if failure and not connected else None,
                message=message,
            ),
        )

    def _empty(self, days: int, code: str, message: str) -> HealthDashboardResponse:
        return HealthDashboardResponse(
            range_days=days,
            sync=HealthSyncMetadata(
                configured=False,
                connected=False,
                source_api=self.client.source_api,
                error_code=code,
                message=message,
            ),
        )

    @staticmethod
    def _latest_source_time(summaries: list[DailyHealthSummary]) -> str | None:
        candidates: list[str] = []
        for summary in summaries:
            for samples in summary.series.values():
                candidates.extend(sample.local_time for sample in samples)
            if summary.sleep.bedtime_end:
                candidates.append(summary.sleep.bedtime_end)
        return max(candidates) if candidates else None

    @staticmethod
    def _apply_previous_changes(summaries: list[DailyHealthSummary]) -> None:
        for previous, current in zip(summaries, summaries[1:]):
            pairs = (
                (previous.latest_heart_rate, current.latest_heart_rate),
                (previous.average_hrv, current.average_hrv),
                (previous.resting_heart_rate, current.resting_heart_rate),
                (previous.recovery.score, current.recovery.score),
                (previous.activity.steps, current.activity.steps),
                (previous.activity.active_minutes, current.activity.active_minutes),
                (previous.sleep.score, current.sleep.score),
            )
            for previous_metric, current_metric in pairs:
                if previous_metric is None or current_metric is None or previous_metric.value == 0:
                    continue
                current_metric.change_from_previous = (
                    (current_metric.value - previous_metric.value)
                    / abs(previous_metric.value)
                    * 100
                )

    def clear_cache(self) -> None:
        self._cache.clear()
        logger.info("ultrahuman.cache.cleared")
