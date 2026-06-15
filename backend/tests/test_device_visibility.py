from pathlib import Path

import pytest

from app.services.device_service import DeviceService, UnsupportedCapabilityError
from app.services.registry import DeviceRegistry


class _FailingHomeAssistant:
    async def entity_registry_for_display(self):
        return []

    async def states(self):
        return [
            {
                "entity_id": "switch.kettle",
                "state": "off",
                "attributes": {"friendly_name": "Kettle"},
            }
        ]

    async def call_service(self, domain: str, service: str, service_data: dict):
        raise RuntimeError("service rejected")


def _registry_with_switch(tmp_path: Path) -> DeviceRegistry:
    config = tmp_path / "devices.yaml"
    config.write_text(
        """
rooms:
  - id: kitchen
    name: Kitchen
    devices:
      - id: kettle
        name: Kettle
        type: switch
        entity_id: switch.kettle
        capabilities: [toggle]
"""
    )
    registry = DeviceRegistry(str(config))
    registry.load()
    registry.update_from_ha_state("switch.kettle", "off", {"friendly_name": "Kettle"})
    return registry


@pytest.mark.asyncio
async def test_control_failure_marks_device_unavailable_and_hidden(tmp_path: Path) -> None:
    registry = _registry_with_switch(tmp_path)
    service = DeviceService(registry, _FailingHomeAssistant())

    with pytest.raises(UnsupportedCapabilityError):
        await service.toggle("kettle")

    device = registry.get_device("kettle")
    assert device is not None
    assert device.state.state == "unavailable"
    assert service.devices() == []
