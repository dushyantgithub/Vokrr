from __future__ import annotations

import asyncio
import logging
import os
import time
from dataclasses import dataclass
from difflib import SequenceMatcher
from typing import Any

import httpx

logger = logging.getLogger(__name__)

SUPPORTED_DOMAINS = {"light", "switch", "fan", "climate", "media_player", "cover"}


class HomeAssistantPipelineError(RuntimeError):
    pass


@dataclass(frozen=True)
class HADevice:
    entity_id: str
    name: str
    room: str | None
    domain: str
    state: str
    aliases: list[str]


@dataclass(frozen=True)
class HAExecutionResult:
    ok: bool
    message: str
    entity_id: str | None = None
    entity_ids: list[str] | None = None
    service: str | None = None
    service_data: dict[str, Any] | None = None


class HAService:
    def __init__(
        self,
        base_url: str | None = None,
        token: str | None = None,
        cache_seconds: float | None = None,
    ) -> None:
        self.base_url = (base_url or os.getenv("HOME_ASSISTANT_URL", "http://localhost:8123")).rstrip("/")
        self.token = token if token is not None else os.getenv("HOME_ASSISTANT_TOKEN", "")
        self.cache_seconds = cache_seconds or float(os.getenv("VOICE_ENTITY_CACHE_SECONDS", "8"))
        self._cache: list[HADevice] = []
        self._cache_time = 0.0
        self._lock = asyncio.Lock()

    @property
    def configured(self) -> bool:
        return bool(self.base_url and self.token)

    @property
    def headers(self) -> dict[str, str]:
        headers = {"Content-Type": "application/json"}
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"
        return headers

    async def entity_context(self) -> dict[str, Any]:
        devices = await self.devices()
        visible_devices = [device for device in devices if include_in_llm_context(device)]
        return {
            "available_devices": [
                {
                    "entity_id": device.entity_id,
                    "name": device.name,
                    "room": device.room,
                    "domain": device.domain,
                    "state": device.state,
                    "aliases": device.aliases,
                }
                for device in visible_devices
            ]
        }

    async def devices(self) -> list[HADevice]:
        now = time.monotonic()
        if self._cache and now - self._cache_time < self.cache_seconds:
            return self._cache

        async with self._lock:
            now = time.monotonic()
            if self._cache and now - self._cache_time < self.cache_seconds:
                return self._cache
            async with httpx.AsyncClient(timeout=6) as client:
                response = await client.get(f"{self.base_url}/api/states", headers=self.headers)
                response.raise_for_status()
            self._cache = simplify_states(response.json())
            self._cache_time = time.monotonic()
            return self._cache

    async def execute(self, decision: dict[str, Any]) -> HAExecutionResult:
        devices = await self.match_devices(decision)
        if not devices:
            return HAExecutionResult(ok=False, message="I could not find that device.")

        action = normalize_optional(decision.get("action"))
        value = decision.get("value")
        executed: list[tuple[HADevice, str, dict[str, Any]]] = []
        async with httpx.AsyncClient(timeout=8) as client:
            for device in devices:
                service_domain, service, service_data = build_service_call(device, action, value)
                response = await client.post(
                    f"{self.base_url}/api/services/{service_domain}/{service}",
                    headers=self.headers,
                    json=service_data,
                )
                if response.status_code >= 400:
                    raise HomeAssistantPipelineError(
                        f"Home Assistant service failed: {response.status_code} {response.text[:240]}"
                    )
                executed.append((device, f"{service_domain}.{service}", service_data))

        self._cache_time = 0.0
        first_device, first_service, first_data = executed[0]
        return HAExecutionResult(
            ok=True,
            message=short_confirmation(first_device, action, count=len(executed)),
            entity_id=first_device.entity_id,
            entity_ids=[device.entity_id for device, _service, _data in executed],
            service=first_service,
            service_data=first_data,
        )

    async def query_state(self, decision: dict[str, Any]) -> HAExecutionResult:
        devices = await self.match_devices(decision)
        if not devices:
            return HAExecutionResult(ok=False, message="I could not find that device.")
        if len(devices) > 1:
            on_count = sum(1 for device in devices if device.state == "on")
            return HAExecutionResult(
                ok=True,
                message=f"{on_count} of {len(devices)} are on.",
                entity_id=devices[0].entity_id,
                entity_ids=[device.entity_id for device in devices],
                service="get_state",
            )
        device = devices[0]
        return HAExecutionResult(
            ok=True,
            message=f"{device.name} is {device.state}.",
            entity_id=device.entity_id,
            entity_ids=[device.entity_id],
            service="get_state",
        )

    async def match_device(self, decision: dict[str, Any]) -> HADevice | None:
        devices = await self.match_devices(decision)
        return devices[0] if len(devices) == 1 else None

    async def match_devices(self, decision: dict[str, Any]) -> list[HADevice]:
        devices = await self.devices()
        domain = normalize_optional(decision.get("domain"))
        name = normalize_optional(decision.get("device_name"))
        room = normalize_optional(decision.get("room"))

        all_candidates = [
            device
            for device in devices
            if include_in_llm_context(device)
        ]
        candidates = [
            device
            for device in all_candidates
            if not domain or domain == "unknown" or device.domain == domain
        ]
        if not candidates:
            candidates = all_candidates

        if room:
            room_matches = [
                device
                for device in candidates
                if device.room and room_matches_device(room, device)
            ]
            if room_matches:
                candidates = room_matches

        if room and is_collective_light_name(name):
            collective = [
                device
                for device in all_candidates
                if device.room and room_matches_device(room, device) and is_light_like(device)
            ]
            if collective:
                return collective

        if name:
            exact = [
                device
                for device in candidates
                if same_text(name, device.name)
                or same_text(name, device.entity_id.replace(".", " ").replace("_", " "))
                or (device.room and same_text(f"{device.room} {device.name}", name))
                or any(same_text(name, alias) for alias in device.aliases)
            ]
            if len(exact) == 1:
                return exact
            if len(exact) > 1:
                return exact

            scored = sorted(
                ((device_score(name, device), device) for device in candidates),
                key=lambda item: item[0],
                reverse=True,
            )
            if scored and scored[0][0] >= 0.82:
                second = scored[1][0] if len(scored) > 1 else 0.0
                if scored[0][0] - second >= 0.05:
                    return [scored[0][1]]

        if room and len(candidates) == 1:
            return candidates
        return []


def simplify_states(rows: list[dict[str, Any]]) -> list[HADevice]:
    devices: list[HADevice] = []
    for row in rows:
        entity_id = row.get("entity_id", "")
        if "." not in entity_id:
            continue
        domain = entity_id.split(".", 1)[0]
        if domain not in SUPPORTED_DOMAINS:
            continue
        attributes = row.get("attributes") or {}
        name = attributes.get("friendly_name") or entity_id.split(".", 1)[1].replace("_", " ").title()
        room = attributes.get("area") or attributes.get("room") or infer_room_from_entity(entity_id)
        devices.append(
            HADevice(
                entity_id=entity_id,
                name=str(name),
                room=str(room) if room else None,
                domain=domain,
                state=str(row.get("state", "unknown")),
                aliases=aliases_for_entity(entity_id, str(name), str(room) if room else None),
            )
        )
    return devices


def build_service_call(device: HADevice, action: str | None, value: Any) -> tuple[str, str, dict[str, Any]]:
    if action == "turn_on":
        return device.domain, "turn_on", {"entity_id": device.entity_id}
    if action == "turn_off":
        return device.domain, "turn_off", {"entity_id": device.entity_id}
    if action == "toggle":
        return device.domain, "toggle", {"entity_id": device.entity_id}
    if action == "set_brightness":
        return "light", "turn_on", {"entity_id": device.entity_id, "brightness_pct": clamp_int(value, 1, 100)}
    if action == "set_speed":
        return "fan", "set_percentage", {"entity_id": device.entity_id, "percentage": clamp_int(value, 0, 100)}
    if action == "set_temperature":
        return "climate", "set_temperature", {"entity_id": device.entity_id, "temperature": float(value)}
    raise HomeAssistantPipelineError(f"Unsupported Home Assistant action: {action}")


def short_confirmation(device: HADevice, action: str | None, count: int = 1) -> str:
    if count > 1:
        if action == "turn_on":
            return f"{count} devices on."
        if action == "turn_off":
            return f"{count} devices off."
        if action == "toggle":
            return f"{count} devices toggled."
        return f"{count} devices updated."
    if action == "turn_on":
        return f"{device.name} on."
    if action == "turn_off":
        return f"{device.name} off."
    if action == "toggle":
        return f"{device.name} toggled."
    if action in {"set_brightness", "set_speed", "set_temperature"}:
        return f"{device.name} updated."
    return "Done."


def clamp_int(value: Any, minimum: int, maximum: int) -> int:
    try:
        parsed = int(float(value))
    except (TypeError, ValueError):
        parsed = maximum
    return max(minimum, min(maximum, parsed))


def normalize_optional(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    if not text or text.lower() in {"null", "none"}:
        return None
    return text


def same_text(left: str, right: str) -> bool:
    return fold(left) == fold(right)


def fold(value: str) -> str:
    return " ".join(value.lower().replace("_", " ").replace("-", " ").split())


def token_subset(target: str, alias: str) -> bool:
    target_tokens = set(fold(target).split())
    alias_tokens = set(fold(alias).split())
    return bool(target_tokens) and target_tokens.issubset(alias_tokens)


def device_score(target: str, device: HADevice) -> float:
    aliases = [
        device.name,
        device.entity_id.replace(".", " ").replace("_", " "),
        *device.aliases,
    ]
    if device.room:
        aliases.append(f"{device.room} {device.name}")
    for alias in aliases:
        if token_subset(target, alias):
            return 1.0
    return max(SequenceMatcher(None, fold(target), fold(alias)).ratio() for alias in aliases)


def is_collective_light_name(name: str | None) -> bool:
    if not name:
        return False
    return fold(name) in {"light", "lights", "bedroom lights", "room lights", "all lights"}


def is_light_like(device: HADevice) -> bool:
    haystack = fold(" ".join([device.name, device.entity_id, *device.aliases]))
    if "backlight" in haystack or "child lock" in haystack:
        return False
    return device.domain == "light" or any(word in haystack.split() for word in ["light", "lights", "bulb", "tubelight", "lamp"])


def include_in_llm_context(device: HADevice) -> bool:
    haystack = fold(" ".join([device.name, device.entity_id]))
    if device.state == "unavailable":
        return False
    if "backlight" in haystack or "child lock" in haystack:
        return False
    return True


def room_matches_device(room: str, device: HADevice) -> bool:
    room_aliases = [device.room or "", *room_aliases_for(device.room), *device.aliases]
    return any(same_text(room, alias) or token_subset(room, alias) for alias in room_aliases if alias)


def aliases_for_entity(entity_id: str, name: str, room: str | None) -> list[str]:
    aliases: list[str] = []
    object_text = entity_id.split(".", 1)[-1].replace("_", " ")
    aliases.append(object_text)
    if room:
        aliases.append(f"{room} {name}")
        for room_alias in room_aliases_for(room):
            aliases.append(f"{room_alias} {name}")
    return unique_text(aliases)


def room_aliases_for(room: str | None) -> list[str]:
    if not room:
        return []
    aliases = parse_room_aliases()
    folded = fold(room)
    out = aliases.get(folded, [])
    for source, targets in aliases.items():
        if folded in {fold(target) for target in targets}:
            out.append(source)
    return unique_text(out)


def parse_room_aliases() -> dict[str, list[str]]:
    default_aliases = (
        "hall:living room|main room|lounge,"
        "living room:hall|main room|lounge,"
        "bedroom:bed room|master bedroom,"
        "gaming room:game room|gaming,"
        "dining room:dinning room|dining,"
        "kitchen:cook room"
    )
    raw = os.getenv("VOICE_ROOM_ALIASES", default_aliases)
    aliases: dict[str, list[str]] = {}
    for pair in raw.split(","):
        if ":" not in pair:
            continue
        source, target_text = pair.split(":", 1)
        source_key = fold(source)
        targets = [target.strip() for target in target_text.split("|") if target.strip()]
        if source_key and targets:
            aliases.setdefault(source_key, []).extend(targets)
    return {key: unique_text(value) for key, value in aliases.items()}


def unique_text(values: list[str]) -> list[str]:
    seen: set[str] = set()
    out: list[str] = []
    for value in values:
        normalized = fold(value)
        if not normalized or normalized in seen:
            continue
        seen.add(normalized)
        out.append(value)
    return out


def infer_room_from_entity(entity_id: str) -> str | None:
    object_id = entity_id.split(".", 1)[-1]
    tokens = object_id.split("_")
    room_tokens: list[str] = []
    stop_tokens = {
        "aircon",
        "backlight",
        "bulb",
        "child",
        "extension",
        "fan",
        "geyser",
        "lamp",
        "lock",
        "plug",
        "socket",
        "switch",
        "tubelight",
        "tibelight",
    }
    ignored_tokens = {"node", "smart", "with", "metering"}
    for token in tokens:
        if token.isdigit() or token in ignored_tokens:
            continue
        if token in stop_tokens:
            break
        room_tokens.append(token)
    if not room_tokens:
        return None
    return " ".join(token.capitalize() for token in room_tokens)
