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
    capabilities: list[Capability] = Field(default_factory=list)
    state: DeviceState = Field(default_factory=DeviceState)


class Room(BaseModel):
    id: str
    name: str
    icon: str = "room"
    devices: list[Device] = Field(default_factory=list)


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


class LoginResponse(BaseModel):
    token: str
    username: str


class VoiceCommandRequest(BaseModel):
    text: str


class VoiceCommandResponse(BaseModel):
    understood: bool
    message: str
    matched_device_ids: list[str] = Field(default_factory=list)


class VoiceEventRequest(BaseModel):
    status: str
    message: str
