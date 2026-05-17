import asyncio

from app.domain.models import Capability, Device, DeviceSetRequest, Room, RoomSetRequest
from app.services.home_assistant import HomeAssistantClient
from app.services.registry import DeviceRegistry, is_unindexed_multigang_base_entity


class DeviceNotFoundError(KeyError):
    pass


class UnsupportedCapabilityError(ValueError):
    pass


class DeviceService:
    def __init__(self, registry: DeviceRegistry, ha_client: HomeAssistantClient) -> None:
        self.registry = registry
        self.ha_client = ha_client
        self._ha_device_metadata_loaded = False

    async def ensure_ha_device_metadata(self) -> None:
        if self._ha_device_metadata_loaded:
            return

        entity_rows = await self.ha_client.entity_registry_for_display()
        self.registry.apply_ha_device_ids(entity_rows)
        self._ha_device_metadata_loaded = True

    async def sync_states(self) -> None:
        await self.ensure_ha_device_metadata()
        seen_entity_ids: set[str] = set()
        for entity in await self.ha_client.states():
            seen_entity_ids.add(entity["entity_id"])
            self.registry.update_from_ha_state(
                entity_id=entity["entity_id"],
                state=entity["state"],
                attributes=entity.get("attributes", {}),
            )
        self.registry.mark_missing_entities_unavailable(seen_entity_ids)

    async def refresh_rooms(self) -> list[Room]:
        self.registry.load()
        self._ha_device_metadata_loaded = False
        await self.sync_states()
        return self.rooms()

    async def _sync_device_state(self, device: Device) -> Device:
        for entity in await self.ha_client.states():
            if entity["entity_id"] == device.entity_id:
                updated = self.registry.update_from_ha_state(
                    entity_id=entity["entity_id"],
                    state=entity["state"],
                    attributes=entity.get("attributes", {}),
                )
                return updated or device

        await self.sync_states()
        raise UnsupportedCapabilityError(
            f"{device.entity_id} is missing or unavailable in Home Assistant"
        )

    async def _sync_device_state_until(self, device: Device, expected_is_on: bool) -> Device:
        latest = await self._sync_device_state(device)
        for _ in range(16):
            if latest.state.is_on == expected_is_on and latest.state.state not in {
                "unknown",
                "unavailable",
            }:
                return latest
            await asyncio.sleep(0.5)
            latest = await self._sync_device_state(device)
        return latest

    def _indexed_sibling_devices(self, device: Device) -> list[Device]:
        entity_ids = set(self.registry.entity_to_device_id)

        base_entity_ids = [device.entity_id]
        if "_" in device.entity_id and not device.entity_id.rsplit("_", 1)[-1].isdigit():
            base_entity_ids.append(device.entity_id.rsplit("_", 1)[0])

        if not any(
            is_unindexed_multigang_base_entity(base_entity_id, entity_ids)
            for base_entity_id in base_entity_ids
        ):
            return []

        siblings: list[Device] = []
        seen_device_ids: set[str] = set()
        for entity_id, sibling_id in self.registry.entity_to_device_id.items():
            if entity_id == device.entity_id or sibling_id in seen_device_ids:
                continue
            if not any(entity_id.startswith(f"{base_entity_id}_") for base_entity_id in base_entity_ids):
                continue
            if not entity_id.rsplit("_", 1)[-1].isdigit():
                continue
            sibling = self.registry.get_device(sibling_id)
            if sibling is not None:
                siblings.append(sibling)
                seen_device_ids.add(sibling_id)
        return siblings

    async def _restore_sibling_states(self, sibling_states: dict[str, bool]) -> None:
        for entity_id, was_on in sibling_states.items():
            domain = entity_id.split(".", 1)[0]
            await self.ha_client.call_service(
                domain,
                "turn_on" if was_on else "turn_off",
                {"entity_id": entity_id},
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

        if device.state.state in {"unknown", "unavailable"}:
            device = await self._sync_device_state(device)

        domain = device.entity_id.split(".", 1)[0]
        expected_is_on = not device.state.is_on
        service = "turn_on" if expected_is_on else "turn_off"
        siblings = self._indexed_sibling_devices(device)
        sibling_states = {sibling.entity_id: sibling.state.is_on for sibling in siblings}
        await self.ha_client.call_service(domain, service, {"entity_id": device.entity_id})
        if siblings:
            await self._restore_sibling_states(sibling_states)
            await asyncio.sleep(2)
            await self.sync_states()
            return await self._sync_device_state(device)
        return await self._sync_device_state_until(device, expected_is_on)

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
            siblings = self._indexed_sibling_devices(device)
            sibling_states = {sibling.entity_id: sibling.state.is_on for sibling in siblings}
            await self.ha_client.call_service(
                domain,
                "turn_on" if request.state else "turn_off",
                {"entity_id": device.entity_id},
            )
            if siblings:
                await self._restore_sibling_states(sibling_states)
                await asyncio.sleep(2)
                await self.sync_states()
                device = await self._sync_device_state(device)
            else:
                device = await self._sync_device_state_until(device, request.state)

        if request.brightness is not None:
            if Capability.brightness not in device.capabilities:
                raise UnsupportedCapabilityError(f"{device.id} does not support brightness")
            brightness = round((request.brightness / 100) * 255)
            await self.ha_client.call_service(
                domain,
                "turn_on",
                {"entity_id": device.entity_id, "brightness": brightness},
            )
            device = await self._sync_device_state(device)

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
            device = await self._sync_device_state(device)

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
            device = await self._sync_device_state(device)

        if request.percentage is not None:
            if Capability.percentage not in device.capabilities:
                raise UnsupportedCapabilityError(f"{device.id} does not support percentage")
            await self.ha_client.call_service(
                domain,
                "set_percentage",
                {"entity_id": device.entity_id, "percentage": request.percentage},
            )
            device = await self._sync_device_state(device)

        return device
