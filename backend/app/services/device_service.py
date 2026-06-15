import asyncio
import logging

from app.domain.models import Capability, Device, DeviceSetRequest, Room, RoomSetRequest
from app.services.home_assistant import HomeAssistantClient
from app.services.registry import (
    DeviceRegistry,
    device_is_visible_controllable,
    device_visibility_reasons,
    is_unindexed_multigang_base_entity,
    toggle_service_for_domain,
)


logger = logging.getLogger(__name__)


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
        logger.info("device.raw provider=home_assistant entity_registry_rows=%s", len(entity_rows))
        self.registry.apply_ha_device_ids(entity_rows)
        self._ha_device_metadata_loaded = True

    async def sync_states(self) -> None:
        await self.ensure_ha_device_metadata()
        seen_entity_ids: set[str] = set()
        states = await self.ha_client.states()
        logger.info("device.raw provider=home_assistant states=%s", len(states))
        for entity in states:
            seen_entity_ids.add(entity["entity_id"])
            device = self.registry.get_device(
                self.registry.entity_to_device_id.get(entity["entity_id"], "")
            )
            if device is not None and self._is_guarded_multigang_base(device):
                self._apply_guarded_base_state(device)
                continue
            self.registry.update_from_ha_state(
                entity_id=entity["entity_id"],
                state=entity["state"],
                attributes=entity.get("attributes", {}),
            )
        self.registry.mark_missing_entities_unavailable(seen_entity_ids)
        logger.info("device.sync visible_count=%s", len(self.registry.visible_devices()))

    def _ensure_controllable(self, device: Device, capability: Capability) -> None:
        if capability not in device.capabilities:
            raise UnsupportedCapabilityError(f"{device.id} does not support {capability.value}")
        if not device_is_visible_controllable(device):
            reasons = "; ".join(device_visibility_reasons(device))
            raise UnsupportedCapabilityError(f"{device.id} is not controllable: {reasons}")

    async def _call_device_service(
        self,
        device: Device,
        domain: str,
        service: str,
        service_data: dict,
    ) -> None:
        logger.info(
            "device.control request id=%s entity_id=%s service=%s.%s data=%s",
            device.id,
            device.entity_id,
            domain,
            service,
            service_data,
        )
        try:
            await self.ha_client.call_service(domain, service, service_data)
        except Exception as exc:
            self.registry.mark_device_unreachable(device.id, str(exc))
            logger.warning(
                "device.control failure id=%s entity_id=%s service=%s.%s reason=%s",
                device.id,
                device.entity_id,
                domain,
                service,
                exc,
            )
            raise UnsupportedCapabilityError(
                f"{device.name} is unreachable or Home Assistant rejected the command"
            ) from exc
        logger.info(
            "device.control success id=%s entity_id=%s service=%s.%s",
            device.id,
            device.entity_id,
            domain,
            service,
        )

    async def refresh_rooms(self) -> list[Room]:
        self.registry.load()
        self._ha_device_metadata_loaded = False
        await self.sync_states()
        return self.rooms()

    async def _sync_device_state(self, device: Device) -> Device:
        if self._is_guarded_multigang_base(device):
            self._apply_guarded_base_state(device)
            return device

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
        self.registry.mark_device_unreachable(
            device.id,
            f"state did not reach expected is_on={expected_is_on}",
        )
        raise UnsupportedCapabilityError(f"{device.name} did not confirm the requested state")

    def _is_guarded_multigang_base(self, device: Device) -> bool:
        return self.registry.is_guarded_multigang_base(device.entity_id)

    def _apply_guarded_base_state(self, device: Device) -> None:
        self.registry.update_from_ha_state(
            device.entity_id,
            device.state.state,
            device.state.attributes,
        )

    def _remember_guarded_base_state(self, device: Device, is_on: bool) -> None:
        self.registry.remember_guarded_base_state(device.entity_id, is_on)

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
        return self.registry.visible_rooms()

    def room(self, room_id: str) -> Room:
        room = self.registry.get_visible_room(room_id)
        if not room:
            raise DeviceNotFoundError(room_id)
        return room

    def devices(self) -> list[Device]:
        return self.registry.visible_devices()

    def device(self, device_id: str) -> Device:
        device = self.registry.get_device(device_id)
        if not device:
            raise DeviceNotFoundError(device_id)
        return device

    async def toggle(self, device_id: str) -> Device:
        device = self.device(device_id)

        if device.state.state in {"unknown", "unavailable"}:
            device = await self._sync_device_state(device)

        self._ensure_controllable(device, Capability.toggle)
        domain = device.entity_id.split(".", 1)[0]
        expected_is_on = not device.state.is_on
        service_domain, service = toggle_service_for_domain(domain, expected_is_on)
        siblings = self._indexed_sibling_devices(device)
        sibling_states = {sibling.entity_id: sibling.state.is_on for sibling in siblings}
        await self._call_device_service(
            device,
            service_domain,
            service,
            {"entity_id": device.entity_id},
        )
        if siblings:
            await self._restore_sibling_states(sibling_states)
            self._remember_guarded_base_state(device, expected_is_on)
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
            if device.state.state in {"unknown", "unavailable"}:
                device = await self._sync_device_state(device)
            self._ensure_controllable(device, Capability.toggle)
            siblings = self._indexed_sibling_devices(device)
            sibling_states = {sibling.entity_id: sibling.state.is_on for sibling in siblings}
            service_domain, service = toggle_service_for_domain(domain, request.state)
            await self._call_device_service(
                device,
                service_domain,
                service,
                {"entity_id": device.entity_id},
            )
            if siblings:
                await self._restore_sibling_states(sibling_states)
                self._remember_guarded_base_state(device, request.state)
                await asyncio.sleep(2)
                await self.sync_states()
                device = await self._sync_device_state(device)
            else:
                device = await self._sync_device_state_until(device, request.state)

        if request.brightness is not None:
            self._ensure_controllable(device, Capability.brightness)
            brightness = round((request.brightness / 100) * 255)
            await self._call_device_service(
                device,
                domain,
                "turn_on",
                {"entity_id": device.entity_id, "brightness": brightness},
            )
            device = await self._sync_device_state(device)

        if request.color_temp_kelvin is not None:
            self._ensure_controllable(device, Capability.color_temperature)
            await self._call_device_service(
                device,
                domain,
                "turn_on",
                {
                    "entity_id": device.entity_id,
                    "color_temp_kelvin": request.color_temp_kelvin,
                },
            )
            device = await self._sync_device_state(device)

        if request.rgb_color is not None:
            self._ensure_controllable(device, Capability.color)
            if len(request.rgb_color) != 3 or any(
                value < 0 or value > 255 for value in request.rgb_color
            ):
                raise UnsupportedCapabilityError("rgb_color must contain three values from 0 to 255")
            await self._call_device_service(
                device,
                domain,
                "turn_on",
                {"entity_id": device.entity_id, "rgb_color": request.rgb_color},
            )
            device = await self._sync_device_state(device)

        if request.percentage is not None:
            self._ensure_controllable(device, Capability.percentage)
            await self._call_device_service(
                device,
                domain,
                "set_percentage",
                {"entity_id": device.entity_id, "percentage": request.percentage},
            )
            device = await self._sync_device_state(device)

        return device
