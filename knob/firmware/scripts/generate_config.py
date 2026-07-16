#!/usr/bin/env python3
"""Generate the ignored firmware config header without exposing secret values."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from urllib.parse import urlparse


FIRMWARE_DIR = Path(__file__).resolve().parents[1]
REPOSITORY_DIR = Path(__file__).resolve().parents[3]
DEFAULT_ENV_FILE = REPOSITORY_DIR / ".env"
DEFAULT_OUTPUT = FIRMWARE_DIR / "src" / "config_private.h"
DEFAULT_PASSWORD_FILE = FIRMWARE_DIR.parent / ".secrets" / "smart-knob-password"


def parse_env(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.exists():
        raise SystemExit(f"Environment file not found: {path}")

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[7:].lstrip()
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in {'"', "'"}:
            value = value[1:-1]
        values[key] = value
    return values


def first(values: dict[str, str], *keys: str, default: str = "") -> str:
    for key in keys:
        value = os.environ.get(key, values.get(key, "")).strip()
        if value:
            return value
    return default


def validate_api_base(api_base: str, allow_loopback: bool) -> str:
    parsed = urlparse(api_base)
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        raise SystemExit("KNOB_API_BASE must be an absolute http(s) URL")
    if not allow_loopback and parsed.hostname in {"localhost", "127.0.0.1", "::1"}:
        raise SystemExit(
            "KNOB_API_BASE points to this computer only. Use the Raspberry Pi LAN hostname or IP."
        )
    return api_base.rstrip("/")


def required(name: str, value: str) -> str:
    if not value:
        raise SystemExit(f"Missing required setting: {name}")
    return value


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--env-file", type=Path, default=DEFAULT_ENV_FILE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--allow-loopback", action="store_true")
    args = parser.parse_args()

    values = parse_env(args.env_file)
    password = first(values, "KNOB_PASSWORD", "VOKRR_KNOB_PASSWORD")
    if not password and DEFAULT_PASSWORD_FILE.exists():
        password = DEFAULT_PASSWORD_FILE.read_text(encoding="utf-8").strip()

    config = {
        "VOKRR_WIFI_SSID": required(
            "KNOB_WIFI_SSID", first(values, "KNOB_WIFI_SSID", "VOKRR_WIFI_SSID", "PRIMARY_SSID")
        ),
        "VOKRR_WIFI_PASSWORD": required(
            "KNOB_WIFI_PASSWORD",
            first(values, "KNOB_WIFI_PASSWORD", "VOKRR_WIFI_PASSWORD", "PRIMARY_SSID_PASSWORD"),
        ),
        "VOKRR_API_BASE": validate_api_base(
            required(
                "KNOB_API_BASE",
                first(values, "KNOB_API_BASE", "VOKRR_API_BASE", "BACKEND_URL"),
            ),
            args.allow_loopback,
        ),
        "VOKRR_USERNAME": first(
            values, "KNOB_USERNAME", "VOKRR_KNOB_USERNAME", default="smart-knob"
        ),
        "VOKRR_PASSWORD": required("KNOB_PASSWORD", password),
        "VOKRR_TIMEZONE": first(values, "KNOB_TIMEZONE", default="IST-5:30"),
    }

    lines = ["#pragma once", ""]
    lines.extend(f"#define {key} {json.dumps(value)}" for key, value in config.items())
    lines.append("")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text("\n".join(lines), encoding="ascii")
    args.output.chmod(0o600)
    print(f"Generated ignored firmware configuration: {args.output}")


if __name__ == "__main__":
    main()
