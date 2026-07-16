from dataclasses import dataclass
from pathlib import Path

from app.core.config import Settings, get_settings
from app.services.auth import AuthService
from app.services.device_service import DeviceService
from app.services.home_assistant import HomeAssistantClient
from app.services.intent import CommandCatalog, IntentService
from app.services.onboarding import OnboardingRepository, OnboardingService
from app.services.network import NetworkService
from app.services.registry import DeviceRegistry
from app.services.scene_service import SceneService
from app.services.spotify import SpotifyService
from app.services.state_sync import StateSyncService
from app.services.ultrahuman import UltrahumanClient, UltrahumanService
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
    onboarding_service: OnboardingService
    command_catalog: CommandCatalog
    intent_service: IntentService
    state_sync: StateSyncService
    network_service: NetworkService
    spotify_service: SpotifyService
    ultrahuman_service: UltrahumanService


_state: AppState | None = None


def build_app_state() -> AppState:
    settings = get_settings()
    Path(settings.auth_database_path).parent.mkdir(parents=True, exist_ok=True)
    Path(settings.onboarding_database_path).parent.mkdir(parents=True, exist_ok=True)
    auth_service = AuthService(settings)
    auth_service.ensure_bootstrap_admin()
    ha_client = HomeAssistantClient(str(settings.home_assistant_url), settings.home_assistant_token)
    onboarding_repository = OnboardingRepository(settings.onboarding_database_path)
    registry = DeviceRegistry(settings.device_config_path, onboarding_repository)
    registry.load()
    websocket_manager = WebSocketManager()
    device_service = DeviceService(registry, ha_client)
    scene_service = SceneService(registry, ha_client)
    onboarding_service = OnboardingService(onboarding_repository, registry, ha_client)
    command_catalog = CommandCatalog(settings.command_config_path)
    intent_service = IntentService(device_service, command_catalog)
    state_sync = StateSyncService(
        ha_client,
        registry,
        websocket_manager,
        discovery_importer=onboarding_service.import_discovered_devices,
        interval_seconds=settings.state_sync_interval_seconds,
    )
    network_service = NetworkService(settings)
    spotify_service = SpotifyService(settings)
    ultrahuman_token = settings.uh_token.get_secret_value()
    ultrahuman_service = UltrahumanService(
        UltrahumanClient(
            ultrahuman_token,
            settings.uh_account.get_secret_value(),
            timeout_seconds=settings.ultrahuman_timeout_seconds,
            max_retries=settings.ultrahuman_max_retries,
        ),
        configured=bool(ultrahuman_token),
        cache_ttl_seconds=settings.ultrahuman_cache_ttl_seconds,
    )
    return AppState(
        settings=settings,
        auth_service=auth_service,
        ha_client=ha_client,
        registry=registry,
        websocket_manager=websocket_manager,
        device_service=device_service,
        scene_service=scene_service,
        onboarding_service=onboarding_service,
        command_catalog=command_catalog,
        intent_service=intent_service,
        state_sync=state_sync,
        network_service=network_service,
        spotify_service=spotify_service,
        ultrahuman_service=ultrahuman_service,
    )


def set_app_state(state: AppState) -> None:
    global _state
    _state = state


def get_app_state() -> AppState:
    if _state is None:
        raise RuntimeError("Application state has not been initialized")
    return _state
