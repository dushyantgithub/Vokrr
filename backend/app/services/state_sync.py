import asyncio
import logging

from app.services.home_assistant import HomeAssistantClient
from app.services.registry import DeviceRegistry
from app.services.websocket_manager import WebSocketManager

logger = logging.getLogger(__name__)


class StateSyncService:
    def __init__(
        self,
        ha_client: HomeAssistantClient,
        registry: DeviceRegistry,
        websocket_manager: WebSocketManager,
    ) -> None:
        self.ha_client = ha_client
        self.registry = registry
        self.websocket_manager = websocket_manager
        self.task: asyncio.Task | None = None

    def start(self) -> None:
        if self.task is None or self.task.done():
            self.task = asyncio.create_task(self._run())

    async def stop(self) -> None:
        if self.task:
            self.task.cancel()
            try:
                await self.task
            except asyncio.CancelledError:
                pass

    async def _run(self) -> None:
        async for event in self.ha_client.subscribe_state_changed():
            data = event.get("data", {})
            new_state = data.get("new_state")
            if not new_state:
                continue

            device = self.registry.update_from_ha_state(
                entity_id=new_state["entity_id"],
                state=new_state["state"],
                attributes=new_state.get("attributes", {}),
            )
            if device:
                await self.websocket_manager.broadcast("device.updated", device.model_dump())

