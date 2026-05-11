from __future__ import annotations

import json
import logging
import os
import platform
import sys
import threading
from pathlib import Path

from PySide6.QtCore import QUrl, Qt
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine

from vokrr_ui.services.audio import play_startup_sound, set_volume_max

APP_ROOT = Path(__file__).resolve().parent
CONFIG_PATH = APP_ROOT / "config" / "app_config.json"
QML_PATH = APP_ROOT / "qml" / "Main.qml"


def load_config() -> dict:
    with CONFIG_PATH.open("r", encoding="utf-8") as config_file:
        return json.load(config_file)


def is_raspberry_pi() -> bool:
    model_path = Path("/proc/device-tree/model")
    try:
        return "Raspberry Pi" in model_path.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return platform.machine().startswith(("arm", "aarch64")) and sys.platform.startswith("linux")


def start_audio(config: dict) -> None:
    def run() -> None:
        try:
            set_volume_max(config)
            play_startup_sound(config)
        except Exception:
            logging.exception("Startup audio failed")

    threading.Thread(target=run, name="vokrr-startup-audio", daemon=True).start()


def main() -> int:
    logging.basicConfig(level=os.getenv("VOKRR_LOG_LEVEL", "INFO"))
    config = load_config()

    app = QGuiApplication(sys.argv)
    app.setApplicationName("Vokrr")
    app.setOrganizationName("Vokrr")

    if is_raspberry_pi() or os.getenv("VOKRR_HIDE_CURSOR") == "1":
        app.setOverrideCursor(Qt.BlankCursor)

    start_audio(config)

    engine = QQmlApplicationEngine()
    engine.rootContext().setContextProperty("appConfig", config)
    engine.load(QUrl.fromLocalFile(str(QML_PATH)))

    if not engine.rootObjects():
        logging.error("Failed to load QML: %s", QML_PATH)
        return 1

    window = engine.rootObjects()[0]
    width = int(config.get("screen_width", 800))
    height = int(config.get("screen_height", 480))
    window.setWidth(width)
    window.setHeight(height)
    window.setMinimumWidth(width)
    window.setMinimumHeight(height)
    window.setMaximumWidth(width)
    window.setMaximumHeight(height)
    window.showFullScreen()

    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
