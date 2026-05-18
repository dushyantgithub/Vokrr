import asyncio
from pathlib import Path

import pytest

from app.domain.models import Capability, Device, DeviceState, DeviceType, Room
from app.services.onboarding import OnboardingRepository, OnboardingService
from app.services.registry import DeviceRegistry
from app.services.state_sync import StateSyncService


class FakeHomeAssistant:
    base_url = "http://home-assistant.test"

    def __init__(self) -> None:
        self.state_rows = [
            {
                "entity_id": "light.new_lamp",
                "state": "on",
                "attributes": {"friendly_name": "New Lamp", "brightness": 128},
            }
        ]
        self.registry_rows = [
            {
                "entity_id": "light.new_lamp",
                "device_id": "ha-new-lamp",
                "name": "New Lamp",
                "area_id": "living_room",
                "platform": "demo",
            }
        ]

    async def states(self):
        return self.state_rows

    async def entity_registry_for_display(self):
        return self.registry_rows

    async def area_registry(self):
        return [{"area_id": "bathroom", "name": "Bathroom"}]

    async def device_registry(self):
        return [{"id": "ha-new-lamp", "area_id": "bathroom", "name": "New Lamp"}]


class FakeMultiGangHomeAssistant:
    base_url = "http://home-assistant.test"

    def __init__(self) -> None:
        self.state_rows = [
            {
                "entity_id": "light.bedroom_switch_backlight",
                "state": "on",
                "attributes": {"friendly_name": "Bedroom Switch Backlight"},
            },
            {
                "entity_id": "switch.bedroom_switch_switch_1",
                "state": "on",
                "attributes": {"friendly_name": "Bulb", "device_class": "switch"},
            },
            {
                "entity_id": "switch.bedroom_switch_switch_2",
                "state": "off",
                "attributes": {"friendly_name": "Tubelight", "device_class": "switch"},
            },
            {
                "entity_id": "switch.bedroom_switch_switch",
                "state": "on",
                "attributes": {"friendly_name": "Fan", "device_class": "switch"},
            },
        ]
        self.registry_rows = [
            {
                "entity_id": row["entity_id"],
                "device_id": "ha-bedroom-switch",
                "name": row["attributes"]["friendly_name"],
                "area_id": "bedroom",
                "platform": "zha",
            }
            for row in self.state_rows
        ]

    async def states(self):
        return self.state_rows

    async def entity_registry_for_display(self):
        return self.registry_rows

    async def area_registry(self):
        return [{"area_id": "bedroom", "name": "Bedroom"}]

    async def device_registry(self):
        return [{"id": "ha-bedroom-switch", "area_id": "bedroom", "name": "Bedroom Switch"}]


def build_registry(tmp_path: Path, repository: OnboardingRepository) -> DeviceRegistry:
    config = tmp_path / "devices.yaml"
    config.write_text(
        """
rooms:
  - id: living_room
    name: Living Room
    devices: []
"""
    )
    registry = DeviceRegistry(str(config), repository)
    registry.load()
    return registry


@pytest.mark.asyncio
async def test_import_discovered_devices_adds_new_ha_device(tmp_path: Path) -> None:
    repository = OnboardingRepository(str(tmp_path / "onboarding.db"))
    registry = build_registry(tmp_path, repository)
    service = OnboardingService(repository, registry, FakeHomeAssistant())

    imported = await service.import_discovered_devices()

    assert len(imported) == 1
    assert imported[0].entity_id == "light.new_lamp"
    assert imported[0].room_id == "bathroom"
    assert Capability.toggle in imported[0].capabilities
    assert Capability.brightness in imported[0].capabilities
    assert registry.get_device(imported[0].id) is not None


@pytest.mark.asyncio
async def test_import_discovered_devices_repairs_existing_imported_room_from_ha_device_area(
    tmp_path: Path,
) -> None:
    repository = OnboardingRepository(str(tmp_path / "onboarding.db"))
    registry = build_registry(tmp_path, repository)
    repository.save_imported_device(
        ha_device_id="ha-new-lamp",
        primary_entity_id="light.new_lamp",
        entity_ids=["light.new_lamp"],
        room_id="living_room",
        display_name="New Lamp",
        device_type="light",
        capabilities=["toggle"],
        is_visible=True,
        is_favorite=False,
    )
    registry.load()
    service = OnboardingService(repository, registry, FakeHomeAssistant())

    changed = await service.import_discovered_devices()

    assert len(changed) == 1
    assert changed[0].room_id == "bathroom"
    assert registry.get_room("bathroom") is not None


@pytest.mark.asyncio
async def test_import_discovered_devices_splits_multi_gang_switch_entities(tmp_path: Path) -> None:
    repository = OnboardingRepository(str(tmp_path / "onboarding.db"))
    registry = build_registry(tmp_path, repository)
    service = OnboardingService(repository, registry, FakeMultiGangHomeAssistant())

    imported = await service.import_discovered_devices()
    imported_by_entity = {device.entity_id: device for device in imported}

    assert set(imported_by_entity) == {
        "switch.bedroom_switch_switch_1",
        "switch.bedroom_switch_switch_2",
        "switch.bedroom_switch_switch",
    }
    assert imported_by_entity["switch.bedroom_switch_switch_1"].name == "Bulb"
    assert imported_by_entity["switch.bedroom_switch_switch_2"].name == "Tubelight"
    assert imported_by_entity["switch.bedroom_switch_switch"].name == "Fan"
    assert imported_by_entity["switch.bedroom_switch_switch"].type == DeviceType.fan
    assert registry.get_room("bedroom") is not None


@pytest.mark.asyncio
async def test_import_discovered_devices_repairs_previously_grouped_switchboard(
    tmp_path: Path,
) -> None:
    repository = OnboardingRepository(str(tmp_path / "onboarding.db"))
    registry = build_registry(tmp_path, repository)
    repository.save_imported_device(
        ha_device_id="ha-bedroom-switch",
        primary_entity_id="light.bedroom_switch_backlight",
        entity_ids=[
            "light.bedroom_switch_backlight",
            "switch.bedroom_switch_switch_1",
            "switch.bedroom_switch_switch_2",
            "switch.bedroom_switch_switch",
        ],
        room_id="living_room",
        display_name="Backlight",
        device_type="light",
        capabilities=["toggle"],
        is_visible=True,
        is_favorite=False,
    )
    registry.load()
    service = OnboardingService(repository, registry, FakeMultiGangHomeAssistant())

    await service.import_discovered_devices()
    room = registry.get_room("bedroom")
    assert room is not None
    devices_by_entity = {device.entity_id: device for device in room.devices}

    assert set(devices_by_entity) == {
        "switch.bedroom_switch_switch_1",
        "switch.bedroom_switch_switch_2",
        "switch.bedroom_switch_switch",
    }
    assert devices_by_entity["switch.bedroom_switch_switch_1"].name == "Bulb"
    assert devices_by_entity["switch.bedroom_switch_switch_2"].name == "Tubelight"
    assert devices_by_entity["switch.bedroom_switch_switch"].type == DeviceType.fan


class FakeStateHomeAssistant:
    async def states(self):
        return [
            {
                "entity_id": "light.new_lamp",
                "state": "on",
                "attributes": {"friendly_name": "New Lamp"},
            }
        ]

    async def subscribe_state_changed(self):
        yield {
            "data": {
                "new_state": {
                    "entity_id": "light.new_lamp",
                    "state": "on",
                    "attributes": {"friendly_name": "New Lamp"},
                }
            }
        }

        while True:
            await asyncio.sleep(60)


class FakeStateRegistry:
    def __init__(self) -> None:
        self.device: Device | None = None

    def update_from_ha_state(self, entity_id: str, state: str, attributes: dict):
        if self.device is None or entity_id != self.device.entity_id:
            return None
        self.device.state = DeviceState(state=state, is_on=state == "on", attributes=attributes)
        return self.device

    def mark_missing_entities_unavailable(self, seen_entity_ids: set[str]) -> None:
        return None

    def all_rooms(self):
        return [Room(id="living_room", name="Living Room", devices=[self.device] if self.device else [])]


class FakeWebsocketManager:
    def __init__(self) -> None:
        self.events = []

    async def broadcast(self, event: str, payload: dict) -> None:
        self.events.append((event, payload))


@pytest.mark.asyncio
async def test_state_sync_imports_unknown_ha_entity_without_device_update_churn() -> None:
    registry = FakeStateRegistry()
    websocket_manager = FakeWebsocketManager()

    async def import_discovered_devices():
        registry.device = Device(
            id="imported_new_lamp",
            name="New Lamp",
            type=DeviceType.light,
            entity_id="light.new_lamp",
            room_id="living_room",
            room_name="Living Room",
            capabilities=[Capability.toggle],
        )
        return [registry.device]

    service = StateSyncService(
        FakeStateHomeAssistant(),
        registry,
        websocket_manager,
        discovery_importer=import_discovered_devices,
    )

    service._schedule_discovery()
    assert service.discovery_task is not None
    await service.discovery_task

    assert [event for event, _ in websocket_manager.events] == ["snapshot"]
    assert websocket_manager.events[0][1]["rooms"][0]["devices"][0]["id"] == "imported_new_lamp"
