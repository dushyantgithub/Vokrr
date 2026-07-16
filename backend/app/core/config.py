from functools import lru_cache

from pydantic import AliasChoices, AnyHttpUrl, Field, SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=("../.env", ".env"),
        env_file_encoding="utf-8",
        extra="ignore",
        populate_by_name=True,
    )

    app_name: str = "Vokrr"
    backend_host: str = "0.0.0.0"
    backend_port: int = 8080
    backend_cors_origins: str = Field(default="")
    home_assistant_url: AnyHttpUrl = "http://localhost:8123"
    home_assistant_token: str = ""
    device_config_path: str = "/app/config/devices.yaml"
    command_config_path: str = "/app/config/commands.yaml"
    auth_database_path: str = "/app/data/auth.db"
    onboarding_database_path: str = "/app/data/onboarding.db"
    app_bootstrap_admin_username: str = Field(
        default="admin",
        validation_alias=AliasChoices("APP_BOOTSTRAP_ADMIN_USERNAME", "APP_USERNAME"),
    )
    app_bootstrap_admin_password: str = Field(
        default="change-this-admin-password",
        validation_alias=AliasChoices("APP_BOOTSTRAP_ADMIN_PASSWORD", "APP_PASSWORD"),
    )
    app_auth_secret: str = "change-this-random-secret"
    access_token_ttl_seconds: int = 900
    refresh_token_ttl_seconds: int = 60 * 60 * 24 * 30
    app_registration_enabled: bool = False
    app_registration_code: str = ""
    kiosk_auto_login: bool = True
    state_sync_interval_seconds: int = 5
    system_restart_command: str = (
        "nohup /bin/sh -c 'sleep 2 && "
        "nsenter --target 1 --mount --uts --ipc --net --pid /bin/systemctl reboot' "
        ">/dev/null 2>&1 &"
    )
    primary_ssid: str = ""
    primary_ssid_password: str = ""
    secondary_ssid: str = ""
    secondary_ssid_password: str = ""
    wifi_interface: str = "wlan0"
    spotify_app_name: str = "Vokrr"
    spotify_app_client_id: str = ""
    spotify_app_client_secret: str = ""
    spotify_redirect_uri: str = "http://127.0.0.1:8080/api/spotify/callback"
    spotify_token_path: str = "/app/data/spotify_tokens.json"
    uh_token: SecretStr = Field(
        default=SecretStr(""),
        validation_alias=AliasChoices("UH_TOKEN", "ULTRAHUMAN_PERSONAL_API_TOKEN"),
    )
    uh_account: SecretStr = Field(
        default=SecretStr(""),
        validation_alias=AliasChoices("UH_ACCOUNT", "ULTRAHUMAN_ACCOUNT_EMAIL"),
    )
    ultrahuman_timeout_seconds: float = Field(default=10, ge=1, le=30)
    ultrahuman_max_retries: int = Field(default=2, ge=0, le=3)
    ultrahuman_cache_ttl_seconds: int = Field(default=300, ge=30, le=3600)

    @property
    def cors_origins(self) -> list[str]:
        return [origin.strip() for origin in self.backend_cors_origins.split(",") if origin.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()
