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
