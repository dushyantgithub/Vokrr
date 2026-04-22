from dataclasses import dataclass
from pathlib import Path

from app.core.config import Settings, get_settings
from app.services.auth import AuthService
from app.services.device_service import DeviceService
from app.services.home_assistant import HomeAssistantClient
from app.services.intent import CommandCatalog, IntentService
from app.services.registry import DeviceRegistry
from app.services.scene_service import SceneService
from app.services.state_sync import StateSyncService
from app.services.websocket_manager import WebSocketManager


@dataclass
class AppState:
    settings: Settings
    auth_service: AuthService
    ha_client: HomeAssistantClient
    registry: DeviceRegistry
    websocket_manager: WebSocketManager
    device_service: DeviceService
    scene_service: SceneService
    command_catalog: CommandCatalog
    intent_service: IntentService
    state_sync: StateSyncService


_state: AppState | None = None


def build_app_state() -> AppState:
    settings = get_settings()
    Path(settings.auth_database_path).parent.mkdir(parents=True, exist_ok=True)
    auth_service = AuthService(settings)
    auth_service.ensure_bootstrap_admin()
    ha_client = HomeAssistantClient(str(settings.home_assistant_url), settings.home_assistant_token)
    registry = DeviceRegistry(settings.device_config_path)
    registry.load()
    websocket_manager = WebSocketManager()
    device_service = DeviceService(registry, ha_client)
    scene_service = SceneService(registry, ha_client)
    command_catalog = CommandCatalog(settings.command_config_path)
    intent_service = IntentService(device_service, command_catalog)
    state_sync = StateSyncService(ha_client, registry, websocket_manager)
    return AppState(
        settings=settings,
        auth_service=auth_service,
        ha_client=ha_client,
        registry=registry,
        websocket_manager=websocket_manager,
        device_service=device_service,
        scene_service=scene_service,
        command_catalog=command_catalog,
        intent_service=intent_service,
        state_sync=state_sync,
    )


def set_app_state(state: AppState) -> None:
    global _state
    _state = state


def get_app_state() -> AppState:
    if _state is None:
        raise RuntimeError("Application state has not been initialized")
    return _state
