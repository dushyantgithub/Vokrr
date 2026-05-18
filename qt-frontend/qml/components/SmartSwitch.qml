import QtQuick

Item {
    id: root

    width: 180
    height: 300

    property bool isOn: false
    property color accentColor: "#4da6ff"

    Rectangle {
        id: frame

        width: 128
        height: 240
        radius: 18

        anchors.centerIn: parent

        gradient: Gradient {
            GradientStop { position: 0.0; color: "#ffffff" }
            GradientStop { position: 0.55; color: "#f4f4f4" }
            GradientStop { position: 1.0; color: "#dddddd" }
        }

        border.color: "#bdbdbd"
        border.width: 2
    }

    Rectangle {
        id: innerGap

        width: 98
        height: 194
        radius: 12

        anchors.centerIn: frame

        color: "#1b1b1b"
        opacity: 0.9
    }

    Rectangle {
        id: rocker

        width: 86
        height: 182
        radius: 10

        anchors.centerIn: innerGap
        anchors.verticalCenterOffset: root.isOn ? -6 : 6

        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: root.isOn ? Qt.lighter(root.accentColor, 1.9) : "#ffffff"
            }
            GradientStop {
                position: 0.55
                color: root.isOn ? Qt.lighter(root.accentColor, 1.5) : "#f5f5f5"
            }
            GradientStop {
                position: 1.0
                color: root.isOn ? Qt.lighter(root.accentColor, 1.2) : "#e5e5e5"
            }
        }

        border.color: root.isOn ? root.accentColor : "#d4d4d4"
        border.width: 1

        Behavior on anchors.verticalCenterOffset {
            NumberAnimation {
                duration: 140
                easing.type: Easing.InOutQuad
            }
        }

        Behavior on border.color {
            ColorAnimation { duration: 180 }
        }
    }

    Rectangle {
        width: 70
        height: 74
        radius: 8

        anchors.horizontalCenter: rocker.horizontalCenter
        anchors.top: rocker.top
        anchors.topMargin: 10

        color: "#ffffff"
        opacity: root.isOn ? 0.35 : 0.55
    }

    Rectangle {
        width: 74
        height: 20
        radius: 8

        anchors.horizontalCenter: rocker.horizontalCenter
        anchors.bottom: rocker.bottom
        anchors.bottomMargin: 8

        color: root.isOn ? root.accentColor : "#bdbdbd"
        opacity: root.isOn ? 0.18 : 0.28
    }

    Rectangle {
        visible: root.isOn

        width: 122
        height: 232
        radius: 18

        anchors.centerIn: frame

        color: root.accentColor
        opacity: 0.12
    }
}
