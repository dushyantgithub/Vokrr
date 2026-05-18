from pathlib import Path
from typing import Any

import yaml

from app.domain.models import Capability, Device, DeviceState, DeviceType, Room, Scene, SceneAction


EXCLUDED_ENTITY_MARKERS = ("child_lock", "child lock", "switch_backlight", "switch backlight")


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

    def all_scenes(self) -> list[Scene]:
        return self.scenes

    def get_room(self, room_id: str) -> Room | None:
        return next((room for room in self.rooms if room.id == room_id), None)

    def get_device(self, device_id: str) -> Device | None:
        return self.devices.get(device_id)

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
        for entity_id, device_id in self.entity_to_device_id.items():
            if entity_id in seen_entity_ids:
                continue
            device = self.devices[device_id]
            device.state = normalize_state("unavailable", {})


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
