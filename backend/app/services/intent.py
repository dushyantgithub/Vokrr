import re

from app.domain.models import DeviceSetRequest, VoiceCommandResponse
from app.services.device_service import DeviceService


class IntentService:
    def __init__(self, device_service: DeviceService) -> None:
        self.device_service = device_service

    async def handle(self, text: str) -> VoiceCommandResponse:
        normalized = re.sub(r"\s+", " ", text.lower().strip())
        if not normalized:
            return VoiceCommandResponse(understood=False, message="I did not hear a command.")

        target_devices = self._match_devices(normalized)
        if not target_devices:
            return VoiceCommandResponse(
                understood=False,
                message="I could not match that command to a configured device.",
            )

        percent = self._extract_percent(normalized)
        turn_on = any(token in normalized for token in ("turn on", "switch on", "set on"))
        turn_off = any(token in normalized for token in ("turn off", "switch off", "set off"))

        changed: list[str] = []
        for device in target_devices:
            if percent is not None:
                payload = (
                    DeviceSetRequest(brightness=percent)
                    if device.type.value == "light"
                    else DeviceSetRequest(percentage=percent)
                )
                await self.device_service.set_device(
                    device.id,
                    payload,
                )
            elif turn_on or turn_off:
                await self.device_service.set_device(
                    device.id,
                    DeviceSetRequest(state=turn_on and not turn_off),
                )
            else:
                await self.device_service.toggle(device.id)
            changed.append(device.id)

        return VoiceCommandResponse(
            understood=True,
            message=f"Done. Updated {len(changed)} device{'s' if len(changed) != 1 else ''}.",
            matched_device_ids=changed,
        )

    def _match_devices(self, normalized: str):
        devices = self.device_service.devices()
        room_matches = [
            room.id for room in self.device_service.rooms() if room.name.lower() in normalized
        ]
        type_matches = [device for device in devices if device.type.value in normalized]
        name_matches = [device for device in devices if device.name.lower() in normalized]

        candidates = name_matches or type_matches or devices
        if room_matches:
            candidates = [device for device in candidates if device.room_id in room_matches]

        if "all" not in normalized and len(candidates) > 1 and not name_matches:
            return []
        return candidates

    @staticmethod
    def _extract_percent(normalized: str) -> int | None:
        match = re.search(r"(\d{1,3})\s*(percent|%)", normalized)
        if not match:
            return None
        return max(0, min(100, int(match.group(1))))
