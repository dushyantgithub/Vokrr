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
