import json
import logging
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
    DeviceType,
    OnboardingCandidate,
    OnboardingIntegration,
    OnboardingRoomOption,
    OnboardingSnapshotResponse,
)
from app.services.home_assistant import HomeAssistantClient
from app.services.registry import (
    DeviceRegistry,
    device_visibility_reasons,
    is_excluded_entity,
    normalize_state,
)


logger = logging.getLogger(__name__)


def _utcnow() -> str:
    return datetime.now(UTC).isoformat()


def _slugify(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", value.strip().lower()).strip("_")


def _titleize(value: str) -> str:
    return value.replace("_", " ").replace("-", " ").strip().title() or "Room"


def _row_area_id(row: dict[str, Any]) -> str | None:
    area_id = row.get("area_id") or row.get("areaId") or row.get("ai")
    return str(area_id) if area_id else None


def _row_device_id(row: dict[str, Any]) -> str | None:
    device_id = row.get("device_id") or row.get("deviceId") or row.get("di")
    return str(device_id) if device_id else None


def _guess_room_id(entity_id: str, friendly_name: str, rooms: list[OnboardingRoomOption]) -> str | None:
    text = f"{friendly_name} {entity_id}".lower().replace("_", " ")
    for room in rooms:
        room_name = room.name.lower()
        room_id_text = room.id.lower().replace("_", " ")
        if text.startswith(room_name) or text.startswith(room_id_text):
            return room.id
    return None


def _raw_entity_name(entity_id: str, row: dict[str, Any], attributes: dict[str, Any]) -> str:
    return str(
        attributes.get("friendly_name")
        or row.get("name")
        or row.get("en")
        or row.get("original_name")
        or row.get("on")
        or entity_id.split(".", 1)[-1].replace("_", " ").title()
    ).strip()


def _display_name(
    entity_id: str,
    row: dict[str, Any],
    attributes: dict[str, Any],
    area_name: str | None = None,
) -> str:
    name = _raw_entity_name(entity_id, row, attributes)
    if area_name and name.casefold() == area_name.casefold():
        name = entity_id.split(".", 1)[-1].replace("_", " ").title()
    if area_name and name.casefold().startswith(f"{area_name.casefold()} "):
        stripped = name[len(area_name) :].strip()
        if stripped:
            name = stripped
    return name or entity_id.split(".", 1)[-1].replace("_", " ").title()


def infer_device_type(entity_id: str, attributes: dict[str, Any]) -> DeviceType:
    domain = entity_id.split(".", 1)[0]
    friendly_name = str(attributes.get("friendly_name") or "").casefold()
    if domain == "light":
        return DeviceType.light
    if domain in {"switch", "input_boolean"}:
        if "fan" in friendly_name:
            return DeviceType.fan
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

    def delete_imported_devices(self, primary_entity_ids: list[str]) -> int:
        if not primary_entity_ids:
            return 0

        placeholders = ",".join("?" for _ in primary_entity_ids)
        with self._connect() as connection:
            cursor = connection.execute(
                f"""
                DELETE FROM imported_devices
                WHERE primary_entity_id IN ({placeholders})
                """,
                tuple(primary_entity_ids),
            )
            return cursor.rowcount


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
        area_names, device_area_ids = await self._ha_area_context()
        platform_counts: dict[str, int] = {}
        for row in registry_rows:
            platform = str(row.get("platform") or row.get("pl") or "unknown")
            platform_counts[platform] = platform_counts.get(platform, 0) + 1
        logger.info(
            "device.raw provider=home_assistant states=%s registry_rows=%s platforms=%s tuya_rows=%s",
            len(states),
            len(registry_rows),
            platform_counts,
            platform_counts.get("tuya", 0),
        )

        state_by_entity_id = {row["entity_id"]: row for row in states if "entity_id" in row}
        imported = self.repository.list_imported_devices()
        imported_entity_ids = {entity_id: row for row in imported for entity_id in row.entity_ids}
        rooms = [
            OnboardingRoomOption(id=room.id, name=room.name, icon=room.icon)
            for room in self.registry.all_rooms()
        ]
        known_room_ids = {room.id for room in rooms}
        for area_id, area_name in area_names.items():
            if area_id not in known_room_ids:
                rooms.append(OnboardingRoomOption(id=area_id, name=area_name, icon="room"))
                known_room_ids.add(area_id)

        if not registry_rows:
            registry_rows = []
            for state_row in states:
                entity_id = str(state_row.get("entity_id", ""))
                attributes = state_row.get("attributes", {})
                friendly_name = str(
                    attributes.get("friendly_name")
                    or entity_id.split(".", 1)[-1].replace("_", " ").title()
                )
                if is_excluded_entity(entity_id, friendly_name, attributes):
                    continue
                domain = entity_id.split(".", 1)[0]
                if domain not in {"switch", "light", "fan", "climate", "media_player", "cover"}:
                    continue
                registry_rows.append(
                    {
                        "entity_id": entity_id,
                        "name": friendly_name,
                        "area_id": _guess_room_id(entity_id, friendly_name, rooms),
                    }
                )

        grouped: dict[str, dict[str, Any]] = {}
        for row in registry_rows:
            entity_id = str(row.get("entity_id") or row.get("entityId") or row.get("entity", ""))
            if not entity_id or entity_id in self.registry.entity_to_device_id:
                continue
            state_row = state_by_entity_id.get(entity_id)
            if state_row is None:
                continue
            attributes = state_row.get("attributes", {})
            if is_excluded_entity(
                entity_id,
                str(row.get("name") or row.get("en") or attributes.get("friendly_name") or ""),
                attributes,
                row,
            ):
                continue
            domain = entity_id.split(".", 1)[0]
            if domain in {"automation", "script", "zone", "person", "sun"}:
                continue

            ha_device_id = _row_device_id(row)
            area_id = (device_area_ids.get(ha_device_id) if ha_device_id else None) or _row_area_id(row)
            area_name = area_names.get(area_id) if area_id else None
            display_name = _display_name(entity_id, row, attributes, area_name)
            device_type = infer_device_type(entity_id, attributes)
            capabilities = infer_capabilities(entity_id, attributes)
            device_state = normalize_state(str(state_row.get("state", "unknown")), attributes)
            probe = Device(
                id=entity_id,
                name=display_name,
                type=device_type,
                entity_id=entity_id,
                room_id=area_id or "",
                room_name=area_name or "",
                source="discovered",
                ha_device_id=ha_device_id,
                entity_ids=[entity_id],
                capabilities=capabilities,
                state=device_state,
            )
            filter_reasons = device_visibility_reasons(probe)
            if filter_reasons:
                logger.info(
                    "device.filtered id=%s entity_id=%s source=discovered room=%s reason=%s",
                    entity_id,
                    entity_id,
                    area_id or "",
                    "; ".join(filter_reasons),
                )
                continue

            group_key = entity_id
            candidate = grouped.setdefault(
                group_key,
                {
                    "id": group_key,
                    "entity_id": entity_id,
                    "entity_ids": [],
                    "ha_device_id": ha_device_id,
                    "name": display_name,
                    "domain": domain,
                    "platform": row.get("platform") or row.get("pl"),
                    "area_id": area_id,
                    "room_id": None,
                    "room_name": area_name,
                    "type": device_type,
                    "capabilities": capabilities,
                    "state": device_state,
                    "already_imported": False,
                    "existing_device_id": None,
                },
            )
            candidate["entity_ids"].append(entity_id)
            entity_capabilities = infer_capabilities(entity_id, attributes)
            merged_capabilities = list(candidate["capabilities"])
            for capability in entity_capabilities:
                if capability not in merged_capabilities:
                    merged_capabilities.append(capability)
            candidate["capabilities"] = merged_capabilities

            if not candidate["area_id"]:
                candidate["area_id"] = area_id
            if candidate["area_id"] and not candidate["room_name"]:
                candidate["room_name"] = area_names.get(candidate["area_id"])

            existing = imported_entity_ids.get(entity_id)
            if existing is not None:
                candidate["already_imported"] = True
                candidate["existing_device_id"] = existing.id
                candidate["room_id"] = existing.room_id
                room = self.registry.get_room(existing.room_id)
                candidate["room_name"] = room.name if room else _titleize(existing.room_id)

        candidates = [OnboardingCandidate(**value) for value in grouped.values()]
        candidates.sort(key=lambda item: (item.already_imported, item.name.lower()))
        return OnboardingSnapshotResponse(
            integrations=self.integration_catalog,
            candidates=candidates,
            rooms=rooms,
            home_assistant_url=self.ha_client.base_url,
        )

    async def _ha_area_context(self) -> tuple[dict[str, str], dict[str, str]]:
        area_names: dict[str, str] = {}
        device_area_ids: dict[str, str] = {}

        try:
            for area in await self.ha_client.area_registry():
                area_id = str(area.get("area_id") or area.get("id") or "")
                if not area_id:
                    continue
                area_names[area_id] = str(area.get("name") or _titleize(area_id))
        except Exception:
            area_names = {}

        try:
            for device in await self.ha_client.device_registry():
                device_id = str(device.get("id") or device.get("device_id") or "")
                area_id = _row_area_id(device)
                if device_id and area_id:
                    device_area_ids[device_id] = area_id
                    area_names.setdefault(area_id, _titleize(area_id))
        except Exception:
            device_area_ids = {}

        return area_names, device_area_ids

    async def sync_imported_device_rooms(self) -> list[Device]:
        registry_rows = await self.ha_client.entity_registry_for_display()
        states = await self.ha_client.states()
        area_names, device_area_ids = await self._ha_area_context()
        row_by_entity_id = {
            str(row.get("entity_id") or row.get("entityId") or row.get("entity") or ""): row
            for row in registry_rows
        }
        state_by_entity_id = {row["entity_id"]: row for row in states if "entity_id" in row}
        changed_device_ids: list[str] = []
        stale_entity_ids: list[str] = []

        for imported in self.repository.list_imported_devices():
            row = row_by_entity_id.get(imported.primary_entity_id)
            state_row = state_by_entity_id.get(imported.primary_entity_id)
            if not row and not state_row:
                stale_entity_ids.append(imported.primary_entity_id)
                continue
            row = row or {}
            attributes = state_row.get("attributes", {}) if state_row else {}
            ha_device_id = _row_device_id(row) or imported.ha_device_id
            area_id = (device_area_ids.get(ha_device_id) if ha_device_id else None) or _row_area_id(row)
            area_name = area_names.get(area_id) if area_id else None
            room_id = area_id or imported.room_id
            display_name = _display_name(imported.primary_entity_id, row, attributes, area_name)
            device_type = infer_device_type(imported.primary_entity_id, attributes).value
            capabilities = [capability.value for capability in infer_capabilities(imported.primary_entity_id, attributes)]
            if not capabilities:
                capabilities = imported.capabilities

            if (
                room_id == imported.room_id
                and display_name == imported.display_name
                and device_type == imported.device_type
                and capabilities == imported.capabilities
                and ha_device_id == imported.ha_device_id
            ):
                continue

            saved = self.repository.save_imported_device(
                ha_device_id=ha_device_id,
                primary_entity_id=imported.primary_entity_id,
                entity_ids=imported.entity_ids,
                room_id=room_id,
                display_name=display_name,
                device_type=device_type,
                capabilities=capabilities,
                is_visible=imported.is_visible,
                is_favorite=imported.is_favorite,
            )
            changed_device_ids.append(saved.id)

        if stale_entity_ids:
            self.repository.delete_imported_devices(stale_entity_ids)

        if changed_device_ids or stale_entity_ids:
            self.registry.load()
        return [
            device
            for device_id in changed_device_ids
            if (device := self.registry.get_device(device_id)) is not None
        ]

    async def repair_grouped_imports(self) -> list[Device]:
        imported = self.repository.list_imported_devices()
        grouped_imports = [record for record in imported if len(record.entity_ids) > 1]
        if not grouped_imports:
            return []

        states = await self.ha_client.states()
        registry_rows = await self.ha_client.entity_registry_for_display()
        area_names, device_area_ids = await self._ha_area_context()
        state_by_entity_id = {row["entity_id"]: row for row in states if "entity_id" in row}
        row_by_entity_id = {
            str(row.get("entity_id") or row.get("entityId") or row.get("entity") or ""): row
            for row in registry_rows
        }

        changed_device_ids: list[str] = []
        for record in grouped_imports:
            for entity_id in record.entity_ids:
                state_row = state_by_entity_id.get(entity_id)
                if not state_row:
                    continue

                attributes = state_row.get("attributes", {})
                row = row_by_entity_id.get(entity_id, {})
                name = _display_name(entity_id, row, attributes)
                if is_excluded_entity(entity_id, name, attributes, row):
                    if entity_id == record.primary_entity_id:
                        saved = self.repository.save_imported_device(
                            ha_device_id=record.ha_device_id,
                            primary_entity_id=record.primary_entity_id,
                            entity_ids=[record.primary_entity_id],
                            room_id=record.room_id,
                            display_name=record.display_name,
                            device_type=record.device_type,
                            capabilities=record.capabilities,
                            is_visible=record.is_visible,
                            is_favorite=record.is_favorite,
                        )
                        changed_device_ids.append(saved.id)
                    continue

                capabilities = infer_capabilities(entity_id, attributes)
                if Capability.toggle not in capabilities:
                    continue

                ha_device_id = _row_device_id(row) or record.ha_device_id
                area_id = (device_area_ids.get(ha_device_id) if ha_device_id else None) or _row_area_id(row)
                area_name = area_names.get(area_id) if area_id else None
                room_id = area_id or record.room_id
                saved = self.repository.save_imported_device(
                    ha_device_id=ha_device_id,
                    primary_entity_id=entity_id,
                    entity_ids=[entity_id],
                    room_id=room_id,
                    display_name=_display_name(entity_id, row, attributes, area_name),
                    device_type=infer_device_type(entity_id, attributes).value,
                    capabilities=[capability.value for capability in capabilities],
                    is_visible=record.is_visible,
                    is_favorite=record.is_favorite,
                )
                changed_device_ids.append(saved.id)

        if changed_device_ids:
            self.registry.load()
        return [
            device
            for device_id in changed_device_ids
            if (device := self.registry.get_device(device_id)) is not None
        ]

    async def import_candidate(self, request: DeviceImportRequest) -> Device:
        snapshot = await self.snapshot()
        candidate = next((item for item in snapshot.candidates if item.id == request.candidate_id), None)
        if candidate is None:
            raise HTTPException(status_code=404, detail="Discovery candidate not found")
        room_ids = {room.id for room in snapshot.rooms}
        if request.room_id not in room_ids:
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

    async def import_discovered_devices(self) -> list[Device]:
        changed_devices = await self.sync_imported_device_rooms()
        repaired_devices = await self.repair_grouped_imports()
        snapshot = await self.snapshot()
        fallback_room_id = snapshot.rooms[0].id if snapshot.rooms else "home_assistant"
        imported_device_ids: list[str] = []

        for candidate in snapshot.candidates:
            if candidate.already_imported:
                continue
            if Capability.toggle not in candidate.capabilities:
                continue

            room_id = candidate.area_id or candidate.room_id or fallback_room_id
            saved = self.repository.save_imported_device(
                ha_device_id=candidate.ha_device_id,
                primary_entity_id=candidate.entity_id,
                entity_ids=candidate.entity_ids,
                room_id=room_id,
                display_name=candidate.name,
                device_type=candidate.type.value,
                capabilities=[capability.value for capability in candidate.capabilities],
                is_visible=True,
                is_favorite=False,
            )
            imported_device_ids.append(saved.id)

        self.registry.load()
        imported_devices = [
            device
            for device_id in imported_device_ids
            if (device := self.registry.get_device(device_id)) is not None
        ]
        return [*changed_devices, *repaired_devices, *imported_devices]
