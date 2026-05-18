from enum import StrEnum
from typing import Any

from pydantic import BaseModel, Field


class DeviceType(StrEnum):
    light = "light"
    switch = "switch"
    fan = "fan"
    sensor = "sensor"
    scene = "scene"
    unknown = "unknown"


class Capability(StrEnum):
    toggle = "toggle"
    brightness = "brightness"
    percentage = "percentage"
    temperature = "temperature"
    color_temperature = "color_temperature"
    color = "color"


class DeviceState(BaseModel):
    state: str = "unknown"
    is_on: bool = False
    brightness: int | None = Field(default=None, ge=0, le=100)
    percentage: int | None = Field(default=None, ge=0, le=100)
    color_temp_kelvin: int | None = None
    rgb_color: list[int] | None = None
    attributes: dict[str, Any] = Field(default_factory=dict)


class Device(BaseModel):
    id: str
    name: str
    type: DeviceType = DeviceType.unknown
    entity_id: str
    room_id: str
    room_name: str
    source: str = "configured"
    ha_device_id: str | None = None
    entity_ids: list[str] = Field(default_factory=list)
    is_visible: bool = True
    is_favorite: bool = False
    capabilities: list[Capability] = Field(default_factory=list)
    state: DeviceState = Field(default_factory=DeviceState)


class Room(BaseModel):
    id: str
    name: str
    icon: str = "room"
    devices: list[Device] = Field(default_factory=list)


class RoomSetRequest(BaseModel):
    state: bool | None = None


class DeviceSetRequest(BaseModel):
    state: bool | None = None
    brightness: int | None = Field(default=None, ge=0, le=100)
    percentage: int | None = Field(default=None, ge=0, le=100)
    color_temp_kelvin: int | None = Field(default=None, ge=1000, le=10000)
    rgb_color: list[int] | None = None


class SceneAction(BaseModel):
    service: str
    target: dict[str, Any] = Field(default_factory=dict)
    data: dict[str, Any] = Field(default_factory=dict)


class Scene(BaseModel):
    id: str
    name: str
    actions: list[SceneAction] = Field(default_factory=list)


class SceneRunResponse(BaseModel):
    id: str
    name: str
    executed_actions: int


class LoginRequest(BaseModel):
    username: str
    password: str


class AuthUser(BaseModel):
    id: str
    username: str
    is_admin: bool = False


class AuthSessionResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "Bearer"
    expires_in: int
    user: AuthUser


class RefreshSessionRequest(BaseModel):
    refresh_token: str


class LogoutRequest(BaseModel):
    refresh_token: str


class RegisterRequest(BaseModel):
    username: str
    password: str
    registration_code: str


class CreateUserRequest(BaseModel):
    username: str
    password: str
    is_admin: bool = False


class SystemRestartResponse(BaseModel):
    accepted: bool = True
    detail: str


class OnboardingRoomOption(BaseModel):
    id: str
    name: str
    icon: str = "room"


class OnboardingIntegration(BaseModel):
    domain: str
    title: str
    description: str
    setup_kind: str
    home_assistant_path: str
    icon: str | None = None


class OnboardingCandidate(BaseModel):
    id: str
    entity_id: str
    entity_ids: list[str] = Field(default_factory=list)
    ha_device_id: str | None = None
    name: str
    domain: str
    platform: str | None = None
    area_id: str | None = None
    room_id: str | None = None
    room_name: str | None = None
    type: DeviceType = DeviceType.unknown
    capabilities: list[Capability] = Field(default_factory=list)
    state: DeviceState = Field(default_factory=DeviceState)
    already_imported: bool = False
    existing_device_id: str | None = None


class OnboardingSnapshotResponse(BaseModel):
    integrations: list[OnboardingIntegration] = Field(default_factory=list)
    candidates: list[OnboardingCandidate] = Field(default_factory=list)
    rooms: list[OnboardingRoomOption] = Field(default_factory=list)
    home_assistant_url: str


class DeviceImportRequest(BaseModel):
    candidate_id: str
    room_id: str
    display_name: str | None = None
    is_visible: bool = True
    is_favorite: bool = False
    capabilities_override: list[Capability] | None = None


class ActivityLogEntry(BaseModel):
    id: int
    user_id: str | None = None
    username: str | None = None
    action: str
    success: bool
    client_ip: str | None = None
    user_agent: str | None = None
    details: dict[str, Any] = Field(default_factory=dict)
    created_at: str


class VoiceCommandRequest(BaseModel):
    text: str


class VoiceCommandResponse(BaseModel):
    understood: bool
    message: str
    matched_device_ids: list[str] = Field(default_factory=list)
    navigate: str | None = None


class VoiceEventRequest(BaseModel):
    status: str
    message: str


class SpotifyAuthUrlResponse(BaseModel):
    configured: bool
    connected: bool = False
    auth_url: str | None = None
    redirect_uri: str | None = None
    scopes: list[str] = Field(default_factory=list)
    detail: str | None = None


class SpotifyPlaybackResponse(BaseModel):
    configured: bool
    connected: bool
    needs_auth: bool = False
    is_playing: bool = False
    title: str = "Connect Spotify"
    artist: str = "Premium account required"
    album_name: str = ""
    album_art_url: str = ""
    progress_ms: int = 0
    duration_ms: int = 45000
    device_name: str = ""
    device_id: str | None = None
    detail: str | None = None


class SpotifyControlResponse(BaseModel):
    ok: bool = True
    detail: str = "ok"
