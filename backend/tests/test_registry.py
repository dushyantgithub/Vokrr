from pathlib import Path

from app.services.registry import DeviceRegistry


def test_registry_loads_rooms_and_devices(tmp_path: Path) -> None:
    config = tmp_path / "devices.yaml"
    config.write_text(
        """
rooms:
  - id: kitchen
    name: Kitchen
    devices:
      - id: kitchen_light
        name: Light
        type: light
        entity_id: light.kitchen
        capabilities: [toggle, brightness]
scenes:
  - id: kitchen_off
    name: Kitchen Off
    actions:
      - service: light.turn_off
        target:
          entity_id: light.kitchen
"""
    )

    registry = DeviceRegistry(str(config))
    registry.load()

    assert registry.get_room("kitchen") is not None
    assert registry.get_device("kitchen_light") is not None
    assert registry.entity_to_device_id["light.kitchen"] == "kitchen_light"
    assert registry.get_scene("kitchen_off") is not None
    assert registry.all_scenes()[0].actions[0].service == "light.turn_off"


class _FakeImportedDevice:
    def __init__(self) -> None:
        self.id = "imported_demo"
        self.ha_device_id = "ha-device-1"
        self.primary_entity_id = "switch.coffee_machine"
        self.entity_ids = ["switch.coffee_machine"]
        self.room_id = "kitchen"
        self.display_name = "Coffee Machine"
        self.device_type = "switch"
        self.capabilities = ["toggle"]
        self.is_visible = True
        self.is_favorite = True


class _FakeOnboardingRepository:
    def list_imported_devices(self) -> list[_FakeImportedDevice]:
        return [_FakeImportedDevice()]


def test_registry_merges_imported_devices(tmp_path: Path) -> None:
    config = tmp_path / "devices.yaml"
    config.write_text(
        """
rooms:
  - id: kitchen
    name: Kitchen
    devices: []
"""
    )

    registry = DeviceRegistry(str(config), onboarding_repository=_FakeOnboardingRepository())
    registry.load()

    imported = registry.get_device("imported_demo")
    assert imported is not None
    assert imported.source == "imported"
    assert imported.entity_id == "switch.coffee_machine"
    assert imported.is_favorite is True
    assert registry.entity_to_device_id["switch.coffee_machine"] == "imported_demo"


class _ImportedDevice:
    def __init__(
        self,
        *,
        record_id: str,
        entity_id: str,
        name: str,
        ha_device_id: str | None = "ha-device",
        room_id: str = "kitchen",
        device_type: str = "switch",
        capabilities: list[str] | None = None,
    ) -> None:
        self.id = record_id
        self.ha_device_id = ha_device_id
        self.primary_entity_id = entity_id
        self.entity_ids = [entity_id]
        self.room_id = room_id
        self.display_name = name
        self.device_type = device_type
        self.capabilities = capabilities or ["toggle"]
        self.is_visible = True
        self.is_favorite = False


class _ImportedRepository:
    def __init__(self, records: list[_ImportedDevice]) -> None:
        self.records = records

    def list_imported_devices(self) -> list[_ImportedDevice]:
        return self.records


def test_visible_devices_hide_duplicates_and_unavailable_entries(tmp_path: Path) -> None:
    config = tmp_path / "devices.yaml"
    config.write_text(
        """
rooms:
  - id: kitchen
    name: Kitchen
    devices:
      - id: configured_kettle
        name: Kettle
        type: switch
        entity_id: switch.kettle
        capabilities: [toggle]
"""
    )

    repository = _ImportedRepository(
        [
            _ImportedDevice(record_id="imported_kettle", entity_id="switch.kettle", name="Kettle"),
            _ImportedDevice(
                record_id="imported_sensor",
                entity_id="sensor.kitchen_temperature",
                name="Temperature",
                device_type="sensor",
                capabilities=["temperature"],
            ),
            _ImportedDevice(record_id="imported_offline", entity_id="switch.offline", name="Offline"),
        ]
    )
    registry = DeviceRegistry(str(config), onboarding_repository=repository)
    registry.load()

    registry.update_from_ha_state("switch.kettle", "off", {"friendly_name": "Kettle"})
    configured = registry.get_device("configured_kettle")
    assert configured is not None
    configured.state = registry.get_device("imported_kettle").state
    registry.update_from_ha_state(
        "sensor.kitchen_temperature",
        "24",
        {"friendly_name": "Temperature", "device_class": "temperature"},
    )
    registry.update_from_ha_state("switch.offline", "unavailable", {"friendly_name": "Offline"})

    visible = registry.visible_devices()

    assert [device.entity_id for device in visible] == ["switch.kettle"]


def test_visible_devices_keep_independent_multichannel_switches(tmp_path: Path) -> None:
    config = tmp_path / "devices.yaml"
    config.write_text(
        """
rooms:
  - id: bedroom
    name: Bedroom
    devices: []
"""
    )

    repository = _ImportedRepository(
        [
            _ImportedDevice(
                record_id="switch_1",
                entity_id="switch.bedroom_switch_switch_1",
                name="Bulb",
                ha_device_id="ha-bedroom-switch",
                room_id="bedroom",
            ),
            _ImportedDevice(
                record_id="switch_2",
                entity_id="switch.bedroom_switch_switch_2",
                name="Tubelight",
                ha_device_id="ha-bedroom-switch",
                room_id="bedroom",
            ),
            _ImportedDevice(
                record_id="switch_fan",
                entity_id="switch.bedroom_switch_switch_fan",
                name="Fan",
                ha_device_id="ha-bedroom-switch",
                room_id="bedroom",
            ),
        ]
    )
    registry = DeviceRegistry(str(config), onboarding_repository=repository)
    registry.load()
    registry.update_from_ha_state("switch.bedroom_switch_switch_1", "off", {})
    registry.update_from_ha_state("switch.bedroom_switch_switch_2", "on", {})
    registry.update_from_ha_state("switch.bedroom_switch_switch_fan", "off", {})

    visible_entities = {device.entity_id for device in registry.visible_devices()}

    assert visible_entities == {
        "switch.bedroom_switch_switch_1",
        "switch.bedroom_switch_switch_2",
        "switch.bedroom_switch_switch_fan",
    }
