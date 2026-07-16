#!/usr/bin/env python3
"""Render the Vokrr GT shell screens with PySide6 for visual regression checks."""

import argparse
import sys
from pathlib import Path

from PySide6.QtCore import QEventLoop, QObject, QSize, QTimer, QUrl
from PySide6.QtGui import QFontDatabase, QGuiApplication
from PySide6.QtQml import QQmlComponent, QQmlEngine
from PySide6.QtQuick import QQuickItem


def device(device_id, name, kind="switch", on=False, capabilities=None, **state):
    snapshot = {"state": "on" if on else "off", "is_on": on, "attributes": {}}
    snapshot.update(state)
    return {
        "id": device_id,
        "name": name,
        "type": kind,
        "entity_id": f"{kind}.{device_id}",
        "room_name": "",
        "capabilities": capabilities or ["toggle"],
        "state": snapshot,
    }


def room(room_id, name, devices):
    for entry in devices:
        entry["room_name"] = name
    return {"id": room_id, "name": name, "devices": devices}


def fixture_rooms():
    return [
        room("living", "Living Room", [
            device("lv_bulb", "Bulb", "light", False, ["toggle", "brightness", "color"], brightness=0, rgb_color=[255, 242, 201]),
            device("lv_fan", "Fan", "fan", True, ["toggle", "percentage"], percentage=45),
            device("lv_socket", "Socket"),
            device("lv_tube", "Tubelight", "light", True, ["toggle", "brightness", "color", "color_temperature"], brightness=80, rgb_color=[91, 140, 255], color_temp_kelvin=4000),
        ]),
        room("kitchen", "Kitchen", [
            device("kt_l", "Left Bulb", "light", False, ["toggle", "brightness"], brightness=0),
            device("kt_r", "Right Bulb", "light", False, ["toggle", "brightness"], brightness=0),
        ]),
        room("gaming", "Gaming Room", [
            device("gm_tube1", "Tubelight 1", "light", True, ["toggle", "brightness", "color"], brightness=72, rgb_color=[168, 121, 255]),
            device("gm_socket", "Socket"),
            device("gm_fan", "Fan", "fan", False, ["toggle", "percentage"], percentage=0),
        ]),
        room("bedroom", "Bedroom", [
            device("bd_tube1", "Tubelight 1", "light", True, ["toggle", "brightness", "color_temperature"], brightness=64, color_temp_kelvin=2700),
            device("bd_aircon", "Aircon Socket"),
            device("bd_bulb", "Bulb", "light", False, ["toggle", "brightness", "color"], brightness=0, rgb_color=[255, 116, 184]),
            device("bd_fan", "Fan", "fan", False, ["toggle", "percentage"], percentage=0),
            device("bd_socket", "Socket"),
            device("bd_tube2", "Tubelight 2", "light", False, ["toggle", "brightness", "color"], brightness=0, rgb_color=[66, 211, 146]),
        ]),
        room("bathroom", "Bathroom", [device("bt_geyser", "Geyser")]),
        room("dining", "Dining Room", [
            device("dn_tube", "Tubelight", "light", False, ["toggle", "brightness", "color_temperature"], brightness=0, color_temp_kelvin=4000),
            device("dn_bulb", "Bulb", "light"),
        ]),
    ]


def fixture_health():
    heart_rate = [58, 61, 64, 62, 67, 72, 69, 65, 63, 60, 62, 64]
    samples = [
        {
            "timestamp": 1_752_665_400 + index * 900,
            "local_time": f"2025-07-16T{(7 + index // 4):02d}:{(index % 4) * 15:02d}:00+05:30",
            "local_date": "2025-07-16",
            "value": value,
            "unit": "bpm",
            "metric": "hr",
            "source": "ultrahuman",
            "quality": "validated",
        }
        for index, value in enumerate(heart_rate)
    ]
    current = {
        "local_date": "2025-07-16",
        "latest_heart_rate": {"value": 64, "unit": "bpm", "timestamp": samples[-1]["local_time"]},
        "average_hrv": {"value": 58, "unit": "ms"},
        "skin_temperature": {"value": 36.4, "unit": "°C"},
        "resting_heart_rate": {"value": 55, "unit": "bpm"},
        "spo2": {"value": 97, "unit": "%"},
        "vo2_max": None,
        "recovery": {
            "score": {"value": 84, "unit": "score"},
            "average_sleep_hrv": {"value": 58, "unit": "ms"},
            "sleep_resting_hr": {"value": 55, "unit": "bpm"},
            "temperature_deviation": {"value": -0.2, "unit": "°C"},
            "heart_rate_drop": None,
            "restorative_sleep": {"value": 42, "unit": "%"},
        },
        "activity": {"steps": {"value": 4321, "unit": "steps"}},
        "sleep": {
            "score": {"value": 88, "unit": "score"},
            "total_sleep_seconds": 27720,
            "time_in_bed_seconds": 29700,
            "efficiency": {"value": 93, "unit": "%"},
            "stages": [
                {"stage": "deep", "seconds": 6600, "percentage": 22.2},
                {"stage": "light", "seconds": 15000, "percentage": 50.5},
                {"stage": "rem", "seconds": 6120, "percentage": 20.6},
                {"stage": "awake", "seconds": 1980, "percentage": 6.7},
            ],
            "timeline": [],
        },
        "series": {"hr": samples},
        "rejected_samples": 0,
    }
    return {
        "range_days": 1,
        "current": current,
        "daily": [current],
        "sync": {
            "configured": True,
            "connected": True,
            "provider": "ultrahuman",
            "source_api": "partner",
            "timezone": "Asia/Kolkata",
            "last_successful_sync_at": "2025-07-16T10:00:00+05:30",
            "latest_source_at": samples[-1]["local_time"],
            "cached": False,
            "stale": False,
            "partial": False,
        },
    }


def wait(milliseconds):
    loop = QEventLoop()
    QTimer.singleShot(milliseconds, loop.quit)
    loop.exec()


def save_item(item, path, size):
    loop = QEventLoop()
    result = item.grabToImage(size)
    saved = {"ok": False}

    def finish():
        saved["ok"] = result.saveToFile(str(path))
        loop.quit()

    result.ready.connect(finish)
    QTimer.singleShot(3000, loop.quit)
    loop.exec()
    return saved["ok"]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=Path("/tmp/vokrr-screens"))
    parser.add_argument("--width", type=int, default=800)
    parser.add_argument("--height", type=int, default=480)
    args = parser.parse_args()

    repo = Path(__file__).resolve().parents[2]
    qml_dir = repo / "qt-frontend" / "qml"
    app = QGuiApplication(sys.argv[:1])
    for font_path in (repo / "qt-frontend" / "assets" / "fonts").glob("*.woff2"):
        QFontDatabase.addApplicationFont(str(font_path))

    engine = QQmlEngine()
    component = QQmlComponent(engine)
    source = f'''import QtQuick
import QtQuick.Controls
ApplicationWindow {{
    width: {args.width}; height: {args.height}; visible: true; color: "black"
    VokrrGtShell {{
        objectName: "shell"; anchors.fill: parent; reducedMotion: true
        backendOnline: true; authenticated: true; realtimeConnected: true
        userName: "Dushyant"
    }}
}}'''.encode()
    component.setData(source, QUrl.fromLocalFile(str(qml_dir / "Preview.qml")))
    if component.isError():
        raise RuntimeError("\n".join(str(error) for error in component.errors()))
    window = component.create()
    if window is None:
        raise RuntimeError("\n".join(str(error) for error in component.errors()))

    shell = window.findChild(QQuickItem, "shell")
    shell.setProperty("rooms", fixture_rooms())
    shell.setProperty("health", fixture_health())
    shell.setProperty("systemInfo", {"raspberry_pi_model": "Raspberry Pi 5 Model B Rev 1.0"})
    args.output.mkdir(parents=True, exist_ok=True)
    wait(350)

    captures = [
        ("dashboard", "dashboard", None),
        ("rooms", "rooms", None),
        ("room", "room", "bedroom"),
        ("health", "health", None),
        ("jarvis", "jarvis", None),
        ("settings", "settings", None),
    ]
    for name, screen, room_id in captures:
        if room_id:
            shell.setProperty("selectedRoomId", room_id)
        shell.setProperty("currentScreen", screen)
        wait(120)
        output_path = args.output / f"{name}-{args.width}x{args.height}.png"
        if not save_item(shell, output_path, QSize(args.width, args.height)):
            raise RuntimeError(f"Could not render {output_path}")
        print(output_path)

    bedroom = fixture_rooms()[3]
    shell.setProperty("selectedRoomId", bedroom["id"])
    shell.setProperty("currentScreen", "room")
    shell.setProperty("selectedColorDevice", bedroom["devices"][0])
    wait(120)
    picker_path = args.output / f"color-picker-{args.width}x{args.height}.png"
    if not save_item(shell, picker_path, QSize(args.width, args.height)):
        raise RuntimeError(f"Could not render {picker_path}")
    print(picker_path)

    window.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
