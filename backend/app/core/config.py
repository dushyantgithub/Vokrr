from functools import lru_cache

from pydantic import AnyHttpUrl, Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    app_name: str = "Quantum Home"
    backend_host: str = "0.0.0.0"
    backend_port: int = 8080
    backend_cors_origins: str = Field(
        default="http://localhost:5173,http://localhost:3000,http://quantum-home.local:3000"
    )
    home_assistant_url: AnyHttpUrl = "http://localhost:8123"
    home_assistant_token: str = ""
    device_config_path: str = "/app/config/devices.yaml"
    command_config_path: str = "/app/config/commands.yaml"
    app_username: str = "admin"
    app_password: str = "change-this-password"
    app_auth_secret: str = "change-this-random-secret"
    kiosk_auto_login: bool = True

    @property
    def cors_origins(self) -> list[str]:
        return [origin.strip() for origin in self.backend_cors_origins.split(",") if origin.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()
