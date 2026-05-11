from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

import requests

APP_ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = APP_ROOT / "config" / "app_config.json"


class HomeAssistantClient:
    def __init__(self, config_path: Path = CONFIG_PATH) -> None:
        self.config = self._load_config(config_path)
        self.base_url = self.config.get("home_assistant_url", "http://homeassistant.local:8123").rstrip("/")
        token_env = self.config.get("home_assistant_token_env", "HA_TOKEN")
        self.token = os.getenv(token_env, "")

    @staticmethod
    def _load_config(config_path: Path) -> dict[str, Any]:
        with config_path.open("r", encoding="utf-8") as config_file:
            return json.load(config_file)

    @property
    def headers(self) -> dict[str, str]:
        headers = {"Content-Type": "application/json"}
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"
        return headers

    def get_states(self) -> list[dict[str, Any]]:
        response = requests.get(f"{self.base_url}/api/states", headers=self.headers, timeout=8)
        response.raise_for_status()
        return response.json()

    def toggle_entity(self, entity_id: str) -> list[dict[str, Any]]:
        domain = entity_id.split(".", 1)[0]
        return self.call_service(domain, "toggle", {"entity_id": entity_id})

    def call_service(self, domain: str, service: str, data: dict[str, Any] | None = None) -> list[dict[str, Any]]:
        response = requests.post(
            f"{self.base_url}/api/services/{domain}/{service}",
            headers=self.headers,
            json=data or {},
            timeout=8,
        )
        response.raise_for_status()
        return response.json()
