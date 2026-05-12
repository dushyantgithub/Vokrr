import asyncio
import logging
from contextlib import suppress

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
        interval_seconds: int = 5,
    ) -> None:
        self.ha_client = ha_client
        self.registry = registry
        self.websocket_manager = websocket_manager
        self.interval_seconds = max(1, interval_seconds)
        self.task: asyncio.Task | None = None
        self.reconcile_task: asyncio.Task | None = None

    def start(self) -> None:
        if self.task is None or self.task.done():
            self.task = asyncio.create_task(self._run())
        if self.reconcile_task is None or self.reconcile_task.done():
            self.reconcile_task = asyncio.create_task(self._reconcile_loop())

    async def stop(self) -> None:
        for task in (self.task, self.reconcile_task):
            if task:
                task.cancel()
                with suppress(asyncio.CancelledError):
                    await task

    async def reconcile_once(self, broadcast: bool = True) -> None:
        seen_entity_ids: set[str] = set()
        for entity in await self.ha_client.states():
            seen_entity_ids.add(entity["entity_id"])
            self.registry.update_from_ha_state(
                entity_id=entity["entity_id"],
                state=entity["state"],
                attributes=entity.get("attributes", {}),
            )
        self.registry.mark_missing_entities_unavailable(seen_entity_ids)
        if broadcast:
            await self.websocket_manager.broadcast(
                "snapshot",
                {"rooms": [room.model_dump() for room in self.registry.all_rooms()]},
            )

    async def _reconcile_loop(self) -> None:
        while True:
            try:
                await self.reconcile_once()
            except Exception:
                logger.exception("Home Assistant state reconciliation failed")
            await asyncio.sleep(self.interval_seconds)

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
