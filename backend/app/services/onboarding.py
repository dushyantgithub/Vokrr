import json
import re
import sqlite3
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Any

from fastapi import HTTPException

from app.domain.models import (
    Capability,
    Device,
    DeviceImportRequest,
    DeviceState,
    DeviceType,
    OnboardingCandidate,
    OnboardingIntegration,
    OnboardingRoomOption,
    OnboardingSnapshotResponse,
)
from app.services.home_assistant import HomeAssistantClient
from app.services.registry import DeviceRegistry, normalize_state


def _utcnow() -> str:
    return datetime.now(UTC).isoformat()


def _slugify(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", value.strip().lower()).strip("_")


def _titleize(value: str) -> str:
    return value.replace("_", " ").replace("-", " ").strip().title() or "Room"


def infer_device_type(entity_id: str, attributes: dict[str, Any]) -> DeviceType:
    domain = entity_id.split(".", 1)[0]
    if domain == "light":
        return DeviceType.light
    if domain in {"switch", "input_boolean"}:
        return DeviceType.switch
    if domain in {"fan", "climate"}:
        return DeviceType.fan
    if domain in {"sensor", "binary_sensor"}:
        return DeviceType.sensor
    if domain == "scene":
        return DeviceType.scene
    if attributes.get("device_class") == "temperature":
        return DeviceType.sensor
    return DeviceType.unknown


def infer_capabilities(entity_id: str, attributes: dict[str, Any]) -> list[Capability]:
    capabilities: list[Capability] = []
    domain = entity_id.split(".", 1)[0]
    state_only_domains = {"switch", "light", "fan", "climate", "media_player", "cover"}
    if domain in state_only_domains:
        capabilities.append(Capability.toggle)
    if isinstance(attributes.get("brightness"), int):
        capabilities.append(Capability.brightness)
    if isinstance(attributes.get("percentage"), int):
        capabilities.append(Capability.percentage)
    if attributes.get("color_temp_kelvin") is not None:
        capabilities.append(Capability.color_temperature)
    if attributes.get("rgb_color") is not None:
        capabilities.append(Capability.color)
    if attributes.get("device_class") == "temperature":
        capabilities.append(Capability.temperature)
    seen: set[Capability] = set()
    ordered: list[Capability] = []
    for capability in capabilities:
        if capability not in seen:
            seen.add(capability)
            ordered.append(capability)
    return ordered


@dataclass
class ImportedDeviceRecord:
    id: str
    ha_device_id: str | None
    primary_entity_id: str
    entity_ids: list[str]
    room_id: str
    display_name: str
    device_type: str
    capabilities: list[str]
    is_visible: bool
    is_favorite: bool


class OnboardingRepository:
    def __init__(self, database_path: str) -> None:
        self.database_path = database_path
        self._initialize()

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.database_path, check_same_thread=False)
        connection.row_factory = sqlite3.Row
        return connection

    def _initialize(self) -> None:
        with self._connect() as connection:
            connection.executescript(
                """
                PRAGMA journal_mode=WAL;

                CREATE TABLE IF NOT EXISTS imported_devices (
                    id TEXT PRIMARY KEY,
                    ha_device_id TEXT,
                    primary_entity_id TEXT NOT NULL UNIQUE,
                    entity_ids_json TEXT NOT NULL,
                    room_id TEXT NOT NULL,
                    display_name TEXT NOT NULL,
                    device_type TEXT NOT NULL,
                    capabilities_json TEXT NOT NULL,
                    is_visible INTEGER NOT NULL DEFAULT 1,
                    is_favorite INTEGER NOT NULL DEFAULT 0,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );
                """
            )

    def list_imported_devices(self) -> list[ImportedDeviceRecord]:
        with self._connect() as connection:
            rows = connection.execute(
                """
                SELECT id, ha_device_id, primary_entity_id, entity_ids_json, room_id, display_name,
                       device_type, capabilities_json, is_visible, is_favorite
                FROM imported_devices
                ORDER BY created_at ASC
                """
            ).fetchall()
        return [
            ImportedDeviceRecord(
                id=str(row["id"]),
                ha_device_id=str(row["ha_device_id"]) if row["ha_device_id"] else None,
                primary_entity_id=str(row["primary_entity_id"]),
                entity_ids=json.loads(str(row["entity_ids_json"])),
                room_id=str(row["room_id"]),
                display_name=str(row["display_name"]),
                device_type=str(row["device_type"]),
                capabilities=json.loads(str(row["capabilities_json"])),
                is_visible=bool(row["is_visible"]),
                is_favorite=bool(row["is_favorite"]),
            )
            for row in rows
        ]

    def find_by_candidate_key(
        self, ha_device_id: str | None, primary_entity_id: str
    ) -> ImportedDeviceRecord | None:
        with self._connect() as connection:
            row = None
            if ha_device_id:
                row = connection.execute(
                    """
                    SELECT * FROM imported_devices
                    WHERE ha_device_id = ?
                    ORDER BY updated_at DESC
                    LIMIT 1
                    """,
                    (ha_device_id,),
                ).fetchone()
            if row is None:
                row = connection.execute(
                    """
                    SELECT * FROM imported_devices
                    WHERE primary_entity_id = ?
                    LIMIT 1
                    """,
                    (primary_entity_id,),
                ).fetchone()
        if row is None:
            return None
        return ImportedDeviceRecord(
            id=str(row["id"]),
            ha_device_id=str(row["ha_device_id"]) if row["ha_device_id"] else None,
            primary_entity_id=str(row["primary_entity_id"]),
            entity_ids=json.loads(str(row["entity_ids_json"])),
            room_id=str(row["room_id"]),
            display_name=str(row["display_name"]),
            device_type=str(row["device_type"]),
            capabilities=json.loads(str(row["capabilities_json"])),
            is_visible=bool(row["is_visible"]),
            is_favorite=bool(row["is_favorite"]),
        )

    def save_imported_device(
        self,
        *,
        ha_device_id: str | None,
        primary_entity_id: str,
        entity_ids: list[str],
        room_id: str,
        display_name: str,
        device_type: str,
        capabilities: list[str],
        is_visible: bool,
        is_favorite: bool,
    ) -> ImportedDeviceRecord:
        existing = self.find_by_candidate_key(ha_device_id, primary_entity_id)
        record_id = existing.id if existing else f"imported_{uuid.uuid4().hex[:10]}"
        now = _utcnow()
        with self._connect() as connection:
            connection.execute(
                """
                INSERT INTO imported_devices (
                    id, ha_device_id, primary_entity_id, entity_ids_json, room_id, display_name,
                    device_type, capabilities_json, is_visible, is_favorite, created_at, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(primary_entity_id) DO UPDATE SET
                    ha_device_id = excluded.ha_device_id,
                    entity_ids_json = excluded.entity_ids_json,
                    room_id = excluded.room_id,
                    display_name = excluded.display_name,
                    device_type = excluded.device_type,
                    capabilities_json = excluded.capabilities_json,
                    is_visible = excluded.is_visible,
                    is_favorite = excluded.is_favorite,
                    updated_at = excluded.updated_at
                """,
                (
                    record_id,
                    ha_device_id,
                    primary_entity_id,
                    json.dumps(entity_ids, separators=(",", ":")),
                    room_id,
                    display_name,
                    device_type,
                    json.dumps(capabilities, separators=(",", ":")),
                    int(is_visible),
                    int(is_favorite),
                    now if existing is None else now,
                    now,
                ),
            )
        saved = self.find_by_candidate_key(ha_device_id, primary_entity_id)
        if saved is None:
            raise RuntimeError("Failed to persist imported device")
        return saved


class OnboardingService:
    def __init__(
        self,
        repository: OnboardingRepository,
        registry: DeviceRegistry,
        ha_client: HomeAssistantClient,
    ) -> None:
        self.repository = repository
        self.registry = registry
        self.ha_client = ha_client
        self.integration_catalog = [
            OnboardingIntegration(
                domain="matter",
                title="Matter",
                description="Add a Matter device in Home Assistant, then import it into Vokrr.",
                setup_kind="handoff",
                home_assistant_path="/config/integrations/dashboard",
                icon="dot.radiowaves.left.and.right",
            ),
            OnboardingIntegration(
                domain="esphome",
                title="ESPHome",
                description="Start the native ESPHome/Home Assistant setup flow, then import discovered entities.",
                setup_kind="handoff",
                home_assistant_path="/config/integrations/dashboard",
                icon="cpu",
            ),
            OnboardingIntegration(
                domain="mqtt",
                title="MQTT",
                description="Use Home Assistant's MQTT integration flow, then map new entities into Vokrr.",
                setup_kind="handoff",
                home_assistant_path="/config/integrations/dashboard",
                icon="antenna.radiowaves.left.and.right",
            ),
            OnboardingIntegration(
                domain="tplink",
                title="TP-Link",
                description="Open Home Assistant integrations and complete TP-Link setup there.",
                setup_kind="handoff",
                home_assistant_path="/config/integrations/dashboard",
                icon="wifi",
            ),
            OnboardingIntegration(
                domain="shelly",
                title="Shelly",
                description="Open Home Assistant integrations and complete Shelly setup there.",
                setup_kind="handoff",
                home_assistant_path="/config/integrations/dashboard",
                icon="lightbulb",
            ),
        ]

    async def snapshot(self) -> OnboardingSnapshotResponse:
        states = await self.ha_client.states()
        registry_rows = await self.ha_client.entity_registry_for_display()

        state_by_entity_id = {row["entity_id"]: row for row in states if "entity_id" in row}
        imported = self.repository.list_imported_devices()
        imported_entity_ids = {entity_id: row for row in imported for entity_id in row.entity_ids}

        grouped: dict[str, dict[str, Any]] = {}
        for row in registry_rows:
            entity_id = str(row.get("entity_id") or row.get("entityId") or row.get("entity", ""))
            if not entity_id or entity_id in self.registry.entity_to_device_id:
                continue
            state_row = state_by_entity_id.get(entity_id)
            if state_row is None:
                continue
            attributes = state_row.get("attributes", {})
            domain = entity_id.split(".", 1)[0]
            if domain in {"automation", "script", "zone", "person", "sun"}:
                continue

            ha_device_id = row.get("device_id") or row.get("deviceId")
            group_key = str(ha_device_id or entity_id)
            candidate = grouped.setdefault(
                group_key,
                {
                    "id": group_key,
                    "entity_id": entity_id,
                    "entity_ids": [],
                    "ha_device_id": ha_device_id,
                    "name": str(
                        row.get("name")
                        or attributes.get("friendly_name")
                        or entity_id.split(".", 1)[1].replace("_", " ").title()
                    ),
                    "domain": domain,
                    "platform": row.get("platform") or row.get("pl"),
                    "area_id": row.get("area_id") or row.get("areaId"),
                    "room_id": None,
                    "room_name": None,
                    "type": infer_device_type(entity_id, attributes),
                    "capabilities": infer_capabilities(entity_id, attributes),
                    "state": normalize_state(str(state_row.get("state", "unknown")), attributes),
                    "already_imported": False,
                    "existing_device_id": None,
                },
            )
            candidate["entity_ids"].append(entity_id)
            existing = imported_entity_ids.get(entity_id)
            if existing is not None:
                candidate["already_imported"] = True
                candidate["existing_device_id"] = existing.id
                candidate["room_id"] = existing.room_id
                room = self.registry.get_room(existing.room_id)
                candidate["room_name"] = room.name if room else _titleize(existing.room_id)

        rooms = [
            OnboardingRoomOption(id=room.id, name=room.name, icon=room.icon)
            for room in self.registry.all_rooms()
        ]
        candidates = [OnboardingCandidate(**value) for value in grouped.values()]
        candidates.sort(key=lambda item: (item.already_imported, item.name.lower()))
        return OnboardingSnapshotResponse(
            integrations=self.integration_catalog,
            candidates=candidates,
            rooms=rooms,
            home_assistant_url=self.ha_client.base_url,
        )

    async def import_candidate(self, request: DeviceImportRequest) -> Device:
        snapshot = await self.snapshot()
        candidate = next((item for item in snapshot.candidates if item.id == request.candidate_id), None)
        if candidate is None:
            raise HTTPException(status_code=404, detail="Discovery candidate not found")
        room = self.registry.get_room(request.room_id)
        if room is None:
            raise HTTPException(status_code=400, detail="Selected room does not exist")

        display_name = request.display_name.strip() if request.display_name else candidate.name
        if not display_name:
            raise HTTPException(status_code=400, detail="Display name is required")
        capabilities = request.capabilities_override or candidate.capabilities
        saved = self.repository.save_imported_device(
            ha_device_id=candidate.ha_device_id,
            primary_entity_id=candidate.entity_id,
            entity_ids=candidate.entity_ids,
            room_id=request.room_id,
            display_name=display_name,
            device_type=candidate.type.value,
            capabilities=[capability.value for capability in capabilities],
            is_visible=request.is_visible,
            is_favorite=request.is_favorite,
        )
        self.registry.load()
        device = self.registry.get_device(saved.id)
        if device is None:
            raise RuntimeError("Imported device was not loaded into the registry")
        return device

