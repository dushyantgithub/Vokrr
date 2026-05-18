import asyncio
import logging
from collections.abc import Awaitable, Callable
from contextlib import suppress

from app.domain.models import Device
from app.services.home_assistant import HomeAssistantClient
from app.services.registry import DeviceRegistry, is_excluded_entity
from app.services.websocket_manager import WebSocketManager

logger = logging.getLogger(__name__)


class StateSyncService:
    def __init__(
        self,
        ha_client: HomeAssistantClient,
        registry: DeviceRegistry,
        websocket_manager: WebSocketManager,
        discovery_importer: Callable[[], Awaitable[list[Device]]] | None = None,
        interval_seconds: int = 5,
    ) -> None:
        self.ha_client = ha_client
        self.registry = registry
        self.websocket_manager = websocket_manager
        self.discovery_importer = discovery_importer
        self.interval_seconds = max(1, interval_seconds)
        self.task: asyncio.Task | None = None
        self.reconcile_task: asyncio.Task | None = None
        self.discovery_task: asyncio.Task | None = None

    def start(self) -> None:
        if self.task is None or self.task.done():
            self.task = asyncio.create_task(self._run())
        if self.reconcile_task is None or self.reconcile_task.done():
            self.reconcile_task = asyncio.create_task(self._reconcile_loop())

    async def stop(self) -> None:
        for task in (self.task, self.reconcile_task, self.discovery_task):
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
                await self.reconcile_once(broadcast=False)
            except Exception:
                logger.exception("Home Assistant state reconciliation failed")
            await asyncio.sleep(self.interval_seconds)

    async def _run(self) -> None:
        async for event in self.ha_client.subscribe_state_changed():
            if event.get("event_type") == "entity_registry_updated":
                self._schedule_discovery()
                continue

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
            elif self._should_discover_from_state(new_state):
                self._schedule_discovery()

    def _should_discover_from_state(self, state: dict) -> bool:
        entity_id = str(state.get("entity_id") or "")
        if not entity_id:
            return False
        attributes = state.get("attributes", {})
        if not isinstance(attributes, dict) or is_excluded_entity(entity_id, attributes=attributes):
            return False
        return entity_id.split(".", 1)[0] in {
            "switch",
            "light",
            "fan",
            "climate",
            "media_player",
            "cover",
        }

    def _schedule_discovery(self) -> None:
        if self.discovery_importer is None:
            return
        if self.discovery_task is not None and not self.discovery_task.done():
            return
        self.discovery_task = asyncio.create_task(self._discover_once())

    async def _discover_once(self) -> None:
        await asyncio.sleep(1)
        if self.discovery_importer is None:
            return
        try:
            imported_devices = await self.discovery_importer()
            if not imported_devices:
                return
            await self.reconcile_once(broadcast=False)
            await self.websocket_manager.broadcast(
                "snapshot",
                {"rooms": [room.model_dump() for room in self.registry.all_rooms()]},
            )
        except Exception:
            logger.exception("Home Assistant device discovery failed")
