from pathlib import Path

import pytest

from app.domain.models import Capability, Device, DeviceState, DeviceType, Room
from app.services.intent import CommandCatalog, IntentService


class FakeDeviceService:
    def __init__(self) -> None:
        self.calls = []
        self._devices = [
            Device(
                id="gaming_room_tubelight",
                name="Tubelight",
                type=DeviceType.light,
                entity_id="light.gaming_room_tubelight",
                room_id="gaming_room",
                room_name="Gaming Room",
                capabilities=[Capability.toggle, Capability.brightness, Capability.color],
                state=DeviceState(state="on", is_on=True),
            ),
            Device(
                id="bedroom_socket",
                name="Socket",
                type=DeviceType.switch,
                entity_id="switch.bedroom_socket",
                room_id="bedroom",
                room_name="Bedroom",
                capabilities=[Capability.toggle],
            ),
        ]

    def devices(self):
        return self._devices

    def rooms(self):
        return [
            Room(id="gaming_room", name="Gaming Room", devices=[self._devices[0]]),
            Room(id="bedroom", name="Bedroom", devices=[self._devices[1]]),
        ]

    async def set_device(self, device_id, request):
        self.calls.append(("set", device_id, request))

    async def toggle(self, device_id):
        self.calls.append(("toggle", device_id, None))


@pytest.fixture()
def command_catalog(tmp_path: Path) -> CommandCatalog:
    config = tmp_path / "commands.yaml"
    config.write_text(
        """
intents:
  turn_off:
    action: turn_off
    templates:
      - "turn off {target}"
      - "switch off {target}"
  set_level:
    action: set_level
    templates:
      - "set {target} to {percent} percent"
"""
    )
    return CommandCatalog(str(config))


@pytest.mark.asyncio
async def test_turn_off_aliases_match_same_device(command_catalog: CommandCatalog) -> None:
    device_service = FakeDeviceService()
    intent = IntentService(device_service, command_catalog)

    response = await intent.handle("switch off gaming room tubelight")

    assert response.understood is True
    assert response.matched_device_ids == ["gaming_room_tubelight"]
    assert device_service.calls[0][0:2] == ("set", "gaming_room_tubelight")
    assert device_service.calls[0][2].state is False


@pytest.mark.asyncio
async def test_turn_off_space_fold_matches_stt_two_word_device_name(
    command_catalog: CommandCatalog,
) -> None:
    """Whisper often writes 'tube light' while devices.yaml has one word 'Tubelight'."""
    device_service = FakeDeviceService()
    intent = IntentService(device_service, command_catalog)

    response = await intent.handle("turn off gaming room tube light")

    assert response.understood is True
    assert response.matched_device_ids == ["gaming_room_tubelight"]


@pytest.mark.asyncio
async def test_room_name_targets_all_room_devices(command_catalog: CommandCatalog) -> None:
    device_service = FakeDeviceService()
    intent = IntentService(device_service, command_catalog)

    response = await intent.handle("turn off bedroom")

    assert response.understood is True
    assert response.matched_device_ids == ["bedroom_socket"]
    assert device_service.calls[0][0:2] == ("set", "bedroom_socket")


@pytest.mark.asyncio
async def test_set_level_template(command_catalog: CommandCatalog) -> None:
    device_service = FakeDeviceService()
    intent = IntentService(device_service, command_catalog)

    response = await intent.handle("set gaming room tubelight to 42 percent")

    assert response.understood is True
    assert response.matched_device_ids == ["gaming_room_tubelight"]
    assert device_service.calls[0][2].brightness == 42
