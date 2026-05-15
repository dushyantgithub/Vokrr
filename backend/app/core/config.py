from functools import lru_cache

from pydantic import AliasChoices, AnyHttpUrl, Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
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
    system_restart_command: str = "nohup /bin/sh -c 'sleep 2 && /sbin/reboot' >/dev/null 2>&1 &"
    primary_ssid: str = ""
    primary_ssid_password: str = ""
    secondary_ssid: str = ""
    secondary_ssid_password: str = ""
    wifi_interface: str = "wlan0"

    @property
    def cors_origins(self) -> list[str]:
        return [origin.strip() for origin in self.backend_cors_origins.split(",") if origin.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()
