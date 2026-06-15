import logging
import re
from pathlib import Path
from typing import Any

import yaml

from app.domain.models import Capability, Device, DeviceState, DeviceType, Room, Scene, SceneAction


logger = logging.getLogger(__name__)

EXCLUDED_ENTITY_MARKERS = ("child_lock", "child lock", "switch_backlight", "switch backlight")
UNREACHABLE_STATES = {"unknown", "unavailable", "offline", "unreachable"}
CONTROL_CAPABILITIES = {
    Capability.toggle,
    Capability.brightness,
    Capability.percentage,
    Capability.color_temperature,
    Capability.color,
}
TURN_ON_OFF_DOMAINS = {"light", "switch", "input_boolean", "fan", "climate", "media_player"}
TOGGLE_SERVICE_DOMAINS = {*TURN_ON_OFF_DOMAINS, "cover"}
BRIGHTNESS_DOMAINS = {"light"}
PERCENTAGE_DOMAINS = {"fan"}
COLOR_DOMAINS = {"light"}


def _normalize_key(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", value.strip().casefold()).strip("_")


def _entity_domain(entity_id: str) -> str:
    return entity_id.split(".", 1)[0] if "." in entity_id else ""


def toggle_service_for_domain(domain: str, state: bool) -> tuple[str, str]:
    if domain == "cover":
        return domain, "open_cover" if state else "close_cover"
    return domain, "turn_on" if state else "turn_off"


def supported_control_capabilities(device: Device) -> set[Capability]:
    domain = _entity_domain(device.entity_id)
    capabilities = set(device.capabilities)
    supported: set[Capability] = set()

    if Capability.toggle in capabilities and domain in TOGGLE_SERVICE_DOMAINS:
        supported.add(Capability.toggle)
    if Capability.brightness in capabilities and domain in BRIGHTNESS_DOMAINS:
        supported.add(Capability.brightness)
    if Capability.percentage in capabilities and domain in PERCENTAGE_DOMAINS:
        supported.add(Capability.percentage)
    if Capability.color_temperature in capabilities and domain in COLOR_DOMAINS:
        supported.add(Capability.color_temperature)
    if Capability.color in capabilities and domain in COLOR_DOMAINS:
        supported.add(Capability.color)

    return supported


def _state_says_unreachable(state: DeviceState) -> bool:
    state_value = str(state.state or "").strip().casefold()
    if state_value in UNREACHABLE_STATES:
        return True

    attributes = state.attributes or {}
    for key in ("available", "online", "connected", "reachable"):
        value = attributes.get(key)
        if isinstance(value, bool) and not value:
            return True

    for key in ("availability", "connection_status", "device_status", "status"):
        value = attributes.get(key)
        if isinstance(value, str) and value.strip().casefold() in UNREACHABLE_STATES:
            return True

    return False


def _attribute_channel(attributes: dict[str, Any]) -> str | None:
    for key in (
        "endpoint_id",
        "endpoint",
        "channel",
        "channel_id",
        "code",
        "dp_code",
        "switch_id",
    ):
        value = attributes.get(key)
        if isinstance(value, (str, int)):
            normalized = _normalize_key(str(value))
            if normalized:
                return normalized
    return None


def _entity_channel(entity_id: str) -> str | None:
    if "." not in entity_id:
        return None

    object_id = entity_id.split(".", 1)[1]
    tokens = object_id.split("_")
    if not tokens:
        return None

    if tokens[-1].isdigit() and any(
        token in {"switch", "channel", "socket", "outlet", "plug", "gang"}
        for token in tokens[:-1]
    ):
        return tokens[-1]

    if tokens[-1] in {"fan"} and any(token in {"switch", "channel"} for token in tokens[:-1]):
        return tokens[-1]

    match = re.search(r"(?:^|_)(?:switch|channel|socket|outlet|plug)_([a-z0-9]+)$", object_id)
    if match:
        return _normalize_key(match.group(1))

    return None


def control_channel(device: Device) -> str | None:
    return _attribute_channel(device.state.attributes or {}) or _entity_channel(device.entity_id)


def device_visibility_reasons(device: Device) -> list[str]:
    reasons: list[str] = []
    domain = _entity_domain(device.entity_id)

    if not device.is_visible:
        reasons.append("marked hidden")
    if not domain:
        reasons.append("missing entity domain")
    if is_excluded_entity(device.entity_id, device.name, device.state.attributes):
        reasons.append("excluded helper/control entity")
    if device.type == DeviceType.sensor or domain in {"sensor", "binary_sensor"}:
        reasons.append("read-only sensor")
    if not set(device.capabilities).intersection(CONTROL_CAPABILITIES):
        reasons.append("missing control capability")
    if not supported_control_capabilities(device):
        reasons.append("unsupported control path")
    if _state_says_unreachable(device.state):
        reasons.append("unreachable state")

    return reasons


def device_is_visible_controllable(device: Device) -> bool:
    return not device_visibility_reasons(device)


def is_unindexed_multigang_base_entity(entity_id: str, entity_ids: set[str]) -> bool:
    if "." not in entity_id or entity_id.rsplit("_", 1)[-1].isdigit():
        return False

    return any(
        candidate.startswith(f"{entity_id}_") and candidate.rsplit("_", 1)[-1].isdigit()
        for candidate in entity_ids
    )


def is_excluded_entity(
    entity_id: str,
    name: str = "",
    attributes: dict[str, Any] | None = None,
    registry_row: dict[str, Any] | None = None,
) -> bool:
    attributes = attributes or {}
    registry_row = registry_row or {}
    text = " ".join(
        str(value)
        for value in (
            entity_id,
            name,
            attributes.get("friendly_name", ""),
            registry_row.get("translation_key", ""),
            registry_row.get("tk", ""),
            registry_row.get("original_name", ""),
            registry_row.get("en", ""),
        )
        if value is not None
    ).lower()
    text = f"{text} {text.replace('_', ' ').replace('-', ' ')}"
    return any(marker in text for marker in EXCLUDED_ENTITY_MARKERS)


class DeviceRegistry:
    def __init__(self, config_path: str, onboarding_repository: Any | None = None) -> None:
        self.config_path = Path(config_path)
        self.onboarding_repository = onboarding_repository
        self.rooms: list[Room] = []
        self.scenes: list[Scene] = []
        self.scenes_by_id: dict[str, Scene] = {}
        self.devices: dict[str, Device] = {}
        self.entity_to_device_id: dict[str, str] = {}
        self.guarded_base_states: dict[str, DeviceState] = {}

    def load(self) -> None:
        if not self.config_path.exists():
            self.rooms = []
            self.scenes = []
            self.scenes_by_id = {}
            self.devices = {}
            self.entity_to_device_id = {}
            return

        raw = yaml.safe_load(self.config_path.read_text()) or {}
        rooms: list[Room] = []
        scenes: list[Scene] = []
        devices: dict[str, Device] = {}
        entity_to_device_id: dict[str, str] = {}

        for room_config in raw.get("rooms", []):
            room_devices: list[Device] = []
            room_id = room_config["id"]
            room_name = room_config["name"]
            for device_config in room_config.get("devices", []):
                if is_excluded_entity(
                    str(device_config.get("entity_id", "")),
                    str(device_config.get("name", "")),
                ):
                    continue
                device = Device(
                    id=device_config["id"],
                    name=device_config["name"],
                    type=DeviceType(device_config.get("type", "unknown")),
                    entity_id=device_config["entity_id"],
                    room_id=room_id,
                    room_name=room_name,
                    source="configured",
                    entity_ids=[device_config["entity_id"]],
                    capabilities=[
                        Capability(capability)
                        for capability in device_config.get("capabilities", [])
                    ],
                )
                room_devices.append(device)
                devices[device.id] = device
                entity_to_device_id[device.entity_id] = device.id

            rooms.append(
                Room(
                    id=room_id,
                    name=room_name,
                    icon=room_config.get("icon", "room"),
                    devices=room_devices,
                )
            )

        for scene_config in raw.get("scenes", []):
            scene = Scene(
                id=scene_config["id"],
                name=scene_config["name"],
                actions=[
                    SceneAction(
                        service=action["service"],
                        target=action.get("target", {}),
                        data=action.get("data", {}),
                    )
                    for action in scene_config.get("actions", [])
                ],
            )
            scenes.append(scene)

        room_lookup = {room.id: room for room in rooms}

        imported_records = (
            self.onboarding_repository.list_imported_devices() if self.onboarding_repository else []
        )

        for imported in imported_records:
            if is_excluded_entity(
                imported.primary_entity_id,
                imported.display_name,
            ) or any(is_excluded_entity(entity_id) for entity_id in imported.entity_ids):
                continue

            imported_room = room_lookup.get(imported.room_id)
            if imported_room is None:
                imported_room = Room(
                    id=imported.room_id,
                    name=imported.room_id.replace("_", " ").title(),
                    icon="room",
                    devices=[],
                )
                rooms.append(imported_room)
                room_lookup[imported.room_id] = imported_room

            imported_device = self._build_imported_device(imported, imported_room.name)
            imported_room.devices.append(imported_device)
            devices[imported_device.id] = imported_device
            for entity_id in imported.entity_ids:
                entity_to_device_id[entity_id] = imported_device.id

        self.rooms = rooms
        self.scenes = scenes
        self.scenes_by_id = {scene.id: scene for scene in scenes}
        self.devices = devices
        self.entity_to_device_id = entity_to_device_id

    def _build_imported_device(self, imported: Any, room_name: str) -> Device:
        primary_entity_id = imported.primary_entity_id
        return Device(
            id=imported.id,
            name=imported.display_name,
            type=DeviceType(imported.device_type),
            entity_id=primary_entity_id,
            room_id=imported.room_id,
            room_name=room_name,
            source="imported",
            ha_device_id=imported.ha_device_id,
            entity_ids=imported.entity_ids,
            is_visible=imported.is_visible,
            is_favorite=imported.is_favorite,
            capabilities=[Capability(capability) for capability in imported.capabilities],
        )

    def apply_ha_device_ids(self, entity_rows: list[dict[str, Any]]) -> None:
        for row in entity_rows:
            entity_id = str(row.get("entity_id") or row.get("entityId") or row.get("ei") or "")
            ha_device_id = row.get("device_id") or row.get("deviceId") or row.get("di")
            if not entity_id or not ha_device_id or is_excluded_entity(entity_id, registry_row=row):
                continue

            device_id = self.entity_to_device_id.get(entity_id)
            if not device_id:
                continue

            self.devices[device_id].ha_device_id = str(ha_device_id)

    def all_rooms(self) -> list[Room]:
        return self.rooms

    def all_devices(self) -> list[Device]:
        return list(self.devices.values())

    def visible_rooms(self) -> list[Room]:
        visible_by_room: dict[str, list[Device]] = {room.id: [] for room in self.rooms}
        for device in self.visible_devices():
            visible_by_room.setdefault(device.room_id, []).append(device)

        return [
            Room(
                id=room.id,
                name=room.name,
                icon=room.icon,
                devices=visible_by_room.get(room.id, []),
            )
            for room in self.rooms
        ]

    def visible_devices(self) -> list[Device]:
        visible: list[Device] = []
        key_to_device_id: dict[str, str] = {}
        device_keys: dict[str, set[str]] = {}

        for device in self._ordered_devices():
            reasons = device_visibility_reasons(device)
            if reasons:
                logger.info(
                    "device.filtered id=%s entity_id=%s source=%s room=%s reason=%s",
                    device.id,
                    device.entity_id,
                    device.source,
                    device.room_id,
                    "; ".join(reasons),
                )
                continue

            keys = self._dedupe_keys(device)
            duplicate_key = next((key for key in keys if key in key_to_device_id), None)
            if duplicate_key is None:
                visible.append(device)
                device_keys[device.id] = keys
                for key in keys:
                    key_to_device_id[key] = device.id
                continue

            existing_id = key_to_device_id[duplicate_key]
            existing = self.devices.get(existing_id)
            if existing is None or self._device_priority(device) > self._device_priority(existing):
                if existing is not None:
                    visible = [item for item in visible if item.id != existing.id]
                    for key in device_keys.get(existing.id, set()):
                        if key_to_device_id.get(key) == existing.id:
                            del key_to_device_id[key]
                    for entity_id in existing.entity_ids or [existing.entity_id]:
                        self.entity_to_device_id[entity_id] = device.id
                visible.append(device)
                device_keys[device.id] = keys
                for key in keys:
                    key_to_device_id[key] = device.id
                winner = device
                loser = existing
            else:
                for entity_id in device.entity_ids or [device.entity_id]:
                    self.entity_to_device_id[entity_id] = existing.id
                winner = existing
                loser = device

            logger.info(
                "device.duplicate key=%s winner_id=%s loser_id=%s winner_entity=%s loser_entity=%s",
                duplicate_key,
                winner.id if winner else "",
                loser.id if loser else "",
                winner.entity_id if winner else "",
                loser.entity_id if loser else "",
            )

        logger.info(
            "device.visible_final count=%s devices=%s",
            len(visible),
            [
                {
                    "id": device.id,
                    "entity_id": device.entity_id,
                    "room_id": device.room_id,
                    "type": device.type.value,
                    "source": device.source,
                }
                for device in visible
            ],
        )
        return visible

    def all_scenes(self) -> list[Scene]:
        return self.scenes

    def get_room(self, room_id: str) -> Room | None:
        return next((room for room in self.rooms if room.id == room_id), None)

    def get_device(self, device_id: str) -> Device | None:
        return self.devices.get(device_id)

    def get_visible_room(self, room_id: str) -> Room | None:
        return next((room for room in self.visible_rooms() if room.id == room_id), None)

    def get_visible_device(self, device_id: str) -> Device | None:
        device = self.devices.get(device_id)
        if device is None or not device_is_visible_controllable(device):
            return None
        return device

    def mark_device_unreachable(self, device_id: str, reason: str) -> Device | None:
        device = self.devices.get(device_id)
        if device is None:
            return None
        device.state = normalize_state(
            "unavailable",
            {
                **device.state.attributes,
                "unreachable_reason": reason,
                "source": "vokrr",
            },
        )
        logger.info(
            "device.filtered id=%s entity_id=%s source=%s room=%s reason=control failure: %s",
            device.id,
            device.entity_id,
            device.source,
            device.room_id,
            reason,
        )
        return device

    def mark_entity_unreachable(self, entity_id: str, reason: str) -> Device | None:
        device_id = self.entity_to_device_id.get(entity_id)
        if not device_id:
            return None
        return self.mark_device_unreachable(device_id, reason)

    def get_scene(self, scene_id: str) -> Scene | None:
        return self.scenes_by_id.get(scene_id)

    def is_guarded_multigang_base(self, entity_id: str) -> bool:
        if entity_id.rsplit("_", 1)[-1].isdigit():
            return False

        entity_ids = set(self.entity_to_device_id)
        base_entity_ids = [entity_id]
        if "_" in entity_id:
            base_entity_ids.append(entity_id.rsplit("_", 1)[0])

        return any(
            is_unindexed_multigang_base_entity(base_entity_id, entity_ids)
            for base_entity_id in base_entity_ids
        )

    def remember_guarded_base_state(self, entity_id: str, is_on: bool) -> DeviceState:
        existing_attributes: dict[str, Any] = {}
        device_id = self.entity_to_device_id.get(entity_id)
        if device_id and (device := self.devices.get(device_id)) is not None:
            existing_attributes = device.state.attributes

        state = DeviceState(
            state="on" if is_on else "off",
            is_on=is_on,
            attributes={
                **existing_attributes,
                "guarded_multigang_base": True,
                "source": "vokrr",
            },
        )
        self.guarded_base_states[entity_id] = state
        if device_id and (device := self.devices.get(device_id)) is not None:
            device.state = state
        return state

    def _guarded_base_state(self, entity_id: str) -> DeviceState:
        remembered = self.guarded_base_states.get(entity_id)
        if remembered is not None:
            return remembered

        return self.remember_guarded_base_state(entity_id, False)

    def update_from_ha_state(self, entity_id: str, state: str, attributes: dict[str, Any]) -> Device | None:
        if is_excluded_entity(entity_id, attributes=attributes):
            return None

        device_id = self.entity_to_device_id.get(entity_id)
        if not device_id:
            return None

        device = self.devices[device_id]
        if self.is_guarded_multigang_base(entity_id):
            device.state = self._guarded_base_state(entity_id)
            return device

        device.state = normalize_state(state, attributes)
        return device

    def mark_missing_entities_unavailable(self, seen_entity_ids: set[str]) -> None:
        for device in self.devices.values():
            entity_ids = set(device.entity_ids or [device.entity_id])
            if entity_ids.intersection(seen_entity_ids):
                continue
            device.state = normalize_state("unavailable", {})

    def _ordered_devices(self) -> list[Device]:
        ordered: list[Device] = []
        seen: set[str] = set()
        for room in self.rooms:
            for device in room.devices:
                if device.id in seen:
                    continue
                ordered.append(device)
                seen.add(device.id)
        for device in self.devices.values():
            if device.id not in seen:
                ordered.append(device)
                seen.add(device.id)
        return ordered

    def _dedupe_keys(self, device: Device) -> set[str]:
        provider = "home_assistant" if device.source in {"configured", "imported"} else device.source
        keys = {
            f"{provider}:entity:{entity_id}"
            for entity_id in (device.entity_ids or [device.entity_id])
            if entity_id
        }

        channel = control_channel(device)
        if device.ha_device_id and channel:
            keys.add(f"{provider}:device:{device.ha_device_id}:channel:{channel}")

        return keys

    def _device_priority(self, device: Device) -> tuple[int, int, int, int, str]:
        domain_rank = {
            "light": 60,
            "fan": 60,
            "switch": 50,
            "input_boolean": 45,
            "media_player": 40,
            "climate": 40,
            "cover": 40,
        }.get(_entity_domain(device.entity_id), 0)
        type_rank = 20 if device.type != DeviceType.unknown else 0
        source_rank = 10 if device.source == "configured" else 5 if device.source == "imported" else 0
        metadata_rank = 4 if device.ha_device_id else 0
        favorite_rank = 2 if device.is_favorite else 0
        capability_rank = len(supported_control_capabilities(device))
        return (
            domain_rank + type_rank + source_rank + metadata_rank + favorite_rank,
            capability_rank,
            -len(device.id),
            -len(device.entity_id),
            device.id,
        )


def normalize_state(state: str, attributes: dict[str, Any]) -> DeviceState:
    brightness = attributes.get("brightness")
    brightness_percent = round((brightness / 255) * 100) if isinstance(brightness, int) else None

    percentage = attributes.get("percentage")
    percentage_value = percentage if isinstance(percentage, int) else None

    return DeviceState(
        state=state,
        is_on=state in {"on", "open", "playing", "home"},
        brightness=brightness_percent,
        percentage=percentage_value,
        color_temp_kelvin=attributes.get("color_temp_kelvin"),
        rgb_color=attributes.get("rgb_color"),
        attributes=attributes,
    )
