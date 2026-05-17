import asyncio
import json
import logging
from collections.abc import AsyncIterator
from typing import Any

import httpx
import websockets

logger = logging.getLogger(__name__)


class HomeAssistantError(RuntimeError):
    pass


class HomeAssistantClient:
    def __init__(self, base_url: str, token: str) -> None:
        self.base_url = base_url.rstrip("/")
        self.token = token

    @property
    def headers(self) -> dict[str, str]:
        headers = {"Content-Type": "application/json"}
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"
        return headers

    async def health(self) -> dict[str, Any]:
        async with httpx.AsyncClient(timeout=5) as client:
            response = await client.get(f"{self.base_url}/api/", headers=self.headers)
            response.raise_for_status()
            return response.json()

    async def states(self) -> list[dict[str, Any]]:
        async with httpx.AsyncClient(timeout=10) as client:
            response = await client.get(f"{self.base_url}/api/states", headers=self.headers)
            response.raise_for_status()
            return response.json()

    async def call_service(
        self,
        domain: str,
        service: str,
        service_data: dict[str, Any] | None = None,
    ) -> list[dict[str, Any]]:
        async with httpx.AsyncClient(timeout=10) as client:
            response = await client.post(
                f"{self.base_url}/api/services/{domain}/{service}",
                headers=self.headers,
                json=service_data or {},
            )
            response.raise_for_status()
            return response.json()

    async def websocket_command(self, command_type: str, **payload: Any) -> Any:
        if not self.token:
            raise HomeAssistantError("HOME_ASSISTANT_TOKEN is required for WebSocket requests")

        ws_url = self.base_url.replace("http://", "ws://").replace("https://", "wss://")
        async with websockets.connect(f"{ws_url}/api/websocket", ping_interval=20) as websocket:
            auth_required = json.loads(await websocket.recv())
            if auth_required.get("type") != "auth_required":
                raise HomeAssistantError(f"Unexpected HA auth handshake: {auth_required}")

            await websocket.send(json.dumps({"type": "auth", "access_token": self.token}))
            auth_ok = json.loads(await websocket.recv())
            if auth_ok.get("type") != "auth_ok":
                raise HomeAssistantError(f"Home Assistant WebSocket auth failed: {auth_ok}")

            request_id = 1
            await websocket.send(json.dumps({"id": request_id, "type": command_type, **payload}))

            while True:
                message = json.loads(await websocket.recv())
                if message.get("id") != request_id or message.get("type") != "result":
                    continue
                if not message.get("success"):
                    raise HomeAssistantError(
                        f"Home Assistant WebSocket command failed: {message.get('error')}"
                    )
                return message.get("result")

    async def entity_registry_for_display(self) -> list[dict[str, Any]]:
        result = await self.websocket_command("config/entity_registry/list_for_display")
        if isinstance(result, list):
            return result
        if not isinstance(result, dict):
            return []

        rows = result.get("entities", [])
        if not isinstance(rows, list):
            return []

        normalized: list[dict[str, Any]] = []
        for row in rows:
            if not isinstance(row, dict):
                continue
            normalized.append(
                {
                    **row,
                    "entity_id": row.get("entity_id") or row.get("ei"),
                    "device_id": row.get("device_id") or row.get("di"),
                    "platform": row.get("platform") or row.get("pl"),
                    "name": row.get("name") or row.get("en"),
                }
            )
        return normalized

    async def area_registry(self) -> list[dict[str, Any]]:
        result = await self.websocket_command("config/area_registry/list")
        return result if isinstance(result, list) else []

    async def device_registry(self) -> list[dict[str, Any]]:
        result = await self.websocket_command("config/device_registry/list")
        return result if isinstance(result, list) else []

    async def subscribe_state_changed(self) -> AsyncIterator[dict[str, Any]]:
        if not self.token:
            raise HomeAssistantError("HOME_ASSISTANT_TOKEN is required for WebSocket updates")

        ws_url = self.base_url.replace("http://", "ws://").replace("https://", "wss://")
        message_id = 1

        while True:
            try:
                async with websockets.connect(f"{ws_url}/api/websocket", ping_interval=20) as websocket:
                    auth_required = json.loads(await websocket.recv())
                    if auth_required.get("type") != "auth_required":
                        raise HomeAssistantError(f"Unexpected HA auth handshake: {auth_required}")

                    await websocket.send(json.dumps({"type": "auth", "access_token": self.token}))
                    auth_ok = json.loads(await websocket.recv())
                    if auth_ok.get("type") != "auth_ok":
                        raise HomeAssistantError(f"Home Assistant WebSocket auth failed: {auth_ok}")

                    for event_type in ("state_changed", "entity_registry_updated"):
                        await websocket.send(
                            json.dumps(
                                {
                                    "id": message_id,
                                    "type": "subscribe_events",
                                    "event_type": event_type,
                                }
                            )
                        )
                        message_id += 1

                    while True:
                        message = json.loads(await websocket.recv())
                        if message.get("type") == "event":
                            yield message["event"]
            except Exception:
                logger.exception("Home Assistant WebSocket disconnected; retrying in 5 seconds")
                await asyncio.sleep(5)
