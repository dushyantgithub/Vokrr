from typing import Literal

from pydantic import BaseModel, Field


class HealthSample(BaseModel):
    timestamp: int
    local_time: str
    local_date: str
    value: float
    unit: str
    metric: str
    source: Literal["ultrahuman"] = "ultrahuman"
    quality: Literal["validated"] = "validated"


class MetricValue(BaseModel):
    value: float
    unit: str
    timestamp: str | None = None
    change_from_previous: float | None = None


class SleepStage(BaseModel):
    stage: Literal["awake", "light", "deep", "rem"]
    seconds: int = Field(ge=0)
    percentage: float = Field(ge=0, le=100)


class SleepInterval(BaseModel):
    start: int
    end: int
    stage: Literal["awake", "light", "deep", "rem"]


class SleepSummary(BaseModel):
    score: MetricValue | None = None
    total_sleep_seconds: int | None = None
    time_in_bed_seconds: int | None = None
    efficiency: MetricValue | None = None
    bedtime_start: str | None = None
    bedtime_end: str | None = None
    stages: list[SleepStage] = Field(default_factory=list)
    timeline: list[SleepInterval] = Field(default_factory=list)
    full_sleep_cycles: int | None = None
    tosses_and_turns: int | None = None
    restorative_sleep: MetricValue | None = None
    morning_alertness_minutes: int | None = None


class RecoverySummary(BaseModel):
    score: MetricValue | None = None
    average_sleep_hrv: MetricValue | None = None
    sleep_resting_hr: MetricValue | None = None
    temperature_deviation: MetricValue | None = None
    heart_rate_drop: MetricValue | None = None
    restorative_sleep: MetricValue | None = None


class ActivitySummary(BaseModel):
    steps: MetricValue | None = None
    active_minutes: MetricValue | None = None
    movement_index: MetricValue | None = None


class DailyHealthSummary(BaseModel):
    local_date: str
    latest_heart_rate: MetricValue | None = None
    average_hrv: MetricValue | None = None
    skin_temperature: MetricValue | None = None
    resting_heart_rate: MetricValue | None = None
    spo2: MetricValue | None = None
    vo2_max: MetricValue | None = None
    recovery: RecoverySummary = Field(default_factory=RecoverySummary)
    activity: ActivitySummary = Field(default_factory=ActivitySummary)
    sleep: SleepSummary = Field(default_factory=SleepSummary)
    series: dict[str, list[HealthSample]] = Field(default_factory=dict)
    rejected_samples: int = 0


class HealthSyncMetadata(BaseModel):
    configured: bool
    connected: bool
    provider: Literal["ultrahuman"] = "ultrahuman"
    source_api: Literal["personal", "partner"] | None = None
    timezone: str = "UTC"
    last_successful_sync_at: str | None = None
    latest_source_at: str | None = None
    cached: bool = False
    stale: bool = False
    partial: bool = False
    error_code: str | None = None
    message: str | None = None


class HealthDashboardResponse(BaseModel):
    range_days: int = Field(ge=1, le=7)
    current: DailyHealthSummary | None = None
    daily: list[DailyHealthSummary] = Field(default_factory=list)
    sync: HealthSyncMetadata
