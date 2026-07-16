#!/usr/bin/env python3
"""Exercise the primary touchscreen interactions with an offscreen Qt window."""

import sys
from pathlib import Path

from PySide6.QtCore import QPoint, Qt, QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlComponent, QQmlEngine
from PySide6.QtQuick import QQuickItem
from PySide6.QtTest import QTest

from render_shell import fixture_rooms, wait


def variant(value):
    return value.toVariant() if hasattr(value, "toVariant") else value


def main():
    repo = Path(__file__).resolve().parents[2]
    qml_dir = repo / "qt-frontend" / "qml"
    app = QGuiApplication(sys.argv[:1])
    engine = QQmlEngine()
    component = QQmlComponent(engine)
    component.setData(
        b'''import QtQuick
import QtQuick.Controls
ApplicationWindow {
    width: 800; height: 480; visible: true
    VokrrGtShell {
        objectName: "shell"; anchors.fill: parent; reducedMotion: true
        backendOnline: true; authenticated: true
    }
}''',
        QUrl.fromLocalFile(str(qml_dir / "Smoke.qml")),
    )
    if component.isError():
        raise RuntimeError("\n".join(str(error) for error in component.errors()))
    window = component.create()
    shell = window.findChild(QQuickItem, "shell")
    shell.setProperty("rooms", fixture_rooms())
    wait(250)

    def click(x, y):
        QTest.mouseClick(window, Qt.LeftButton, Qt.NoModifier, QPoint(x, y))
        wait(100)

    toggles = []
    sets = []
    wake_changes = []
    shell.deviceToggleRequested.connect(lambda device: toggles.append(variant(device)))
    shell.deviceSetRequested.connect(
        lambda device, payload: sets.append((variant(device), variant(payload)))
    )
    shell.wakeWordRequested.connect(lambda enabled: wake_changes.append(enabled))

    click(350, 439)
    assert shell.property("currentScreen") == "rooms"
    click(120, 130)
    assert shell.property("currentScreen") == "room"
    assert shell.property("selectedRoomId") == "living"
    click(230, 184)
    assert toggles[-1]["id"] == "lv_bulb"
    click(225, 102)
    assert variant(shell.property("selectedColorDevice"))["id"] == "lv_bulb"
    click(210, 311)
    assert sets[-1][1]["rgb_color"] == [255, 173, 89]
    click(50, 50)
    click(500, 439)
    assert shell.property("currentScreen") == "settings"
    click(734, 101)
    assert wake_changes == [False]

    window.close()
    app.quit()
    print("Vokrr shell interaction smoke test passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
