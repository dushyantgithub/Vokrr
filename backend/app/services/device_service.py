from app.domain.models import Capability, Device, DeviceSetRequest, Room, RoomSetRequest
from app.services.home_assistant import HomeAssistantClient
from app.services.registry import DeviceRegistry


class DeviceNotFoundError(KeyError):
    pass


class UnsupportedCapabilityError(ValueError):
    pass


class DeviceService:
    def __init__(self, registry: DeviceRegistry, ha_client: HomeAssistantClient) -> None:
        self.registry = registry
        self.ha_client = ha_client

    async def sync_states(self) -> None:
        for entity in await self.ha_client.states():
            self.registry.update_from_ha_state(
                entity_id=entity["entity_id"],
                state=entity["state"],
                attributes=entity.get("attributes", {}),
            )

    def rooms(self) -> list[Room]:
        return self.registry.all_rooms()

    def room(self, room_id: str) -> Room:
        room = self.registry.get_room(room_id)
        if not room:
            raise DeviceNotFoundError(room_id)
        return room

    def devices(self) -> list[Device]:
        return self.registry.all_devices()

    def device(self, device_id: str) -> Device:
        device = self.registry.get_device(device_id)
        if not device:
            raise DeviceNotFoundError(device_id)
        return device

    async def toggle(self, device_id: str) -> Device:
        device = self.device(device_id)
        if Capability.toggle not in device.capabilities:
            raise UnsupportedCapabilityError(f"{device.id} does not support toggle")

        domain = device.entity_id.split(".", 1)[0]
        service = "turn_off" if device.state.is_on else "turn_on"
        await self.ha_client.call_service(domain, service, {"entity_id": device.entity_id})
        device.state.is_on = not device.state.is_on
        device.state.state = "on" if device.state.is_on else "off"
        return device

    async def set_room(self, room_id: str, request: RoomSetRequest) -> Room:
        room = self.room(room_id)
        if request.state is None:
            raise UnsupportedCapabilityError("Room state update requires an on/off value")

        for device in room.devices:
            if Capability.toggle not in device.capabilities:
                continue
            await self.set_device(device.id, DeviceSetRequest(state=request.state))

        return room

    async def set_device(self, device_id: str, request: DeviceSetRequest) -> Device:
        device = self.device(device_id)
        domain = device.entity_id.split(".", 1)[0]

        if request.state is not None:
            if Capability.toggle not in device.capabilities:
                raise UnsupportedCapabilityError(f"{device.id} does not support on/off state")
            await self.ha_client.call_service(
                domain,
                "turn_on" if request.state else "turn_off",
                {"entity_id": device.entity_id},
            )
            device.state.is_on = request.state
            device.state.state = "on" if request.state else "off"

        if request.brightness is not None:
            if Capability.brightness not in device.capabilities:
                raise UnsupportedCapabilityError(f"{device.id} does not support brightness")
            brightness = round((request.brightness / 100) * 255)
            await self.ha_client.call_service(
                domain,
                "turn_on",
                {"entity_id": device.entity_id, "brightness": brightness},
            )
            device.state.is_on = True
            device.state.state = "on"
            device.state.brightness = request.brightness

        if request.color_temp_kelvin is not None:
            if Capability.color_temperature not in device.capabilities:
                raise UnsupportedCapabilityError(
                    f"{device.id} does not support color temperature"
                )
            await self.ha_client.call_service(
                domain,
                "turn_on",
                {
                    "entity_id": device.entity_id,
                    "color_temp_kelvin": request.color_temp_kelvin,
                },
            )
            device.state.is_on = True
            device.state.state = "on"
            device.state.color_temp_kelvin = request.color_temp_kelvin

        if request.rgb_color is not None:
            if Capability.color not in device.capabilities:
                raise UnsupportedCapabilityError(f"{device.id} does not support color")
            if len(request.rgb_color) != 3 or any(
                value < 0 or value > 255 for value in request.rgb_color
            ):
                raise UnsupportedCapabilityError("rgb_color must contain three values from 0 to 255")
            await self.ha_client.call_service(
                domain,
                "turn_on",
                {"entity_id": device.entity_id, "rgb_color": request.rgb_color},
            )
            device.state.is_on = True
            device.state.state = "on"
            device.state.rgb_color = request.rgb_color

        if request.percentage is not None:
            if Capability.percentage not in device.capabilities:
                raise UnsupportedCapabilityError(f"{device.id} does not support percentage")
            await self.ha_client.call_service(
                domain,
                "set_percentage",
                {"entity_id": device.entity_id, "percentage": request.percentage},
            )
            device.state.percentage = request.percentage

        return device
