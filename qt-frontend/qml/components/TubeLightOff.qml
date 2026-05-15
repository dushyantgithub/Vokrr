import QtQuick

Item {
    id: root

    width: 560
    height: 140

    property bool isOn: false
    property color glowColor: "#fff4cf"

    Rectangle {
        visible: root.isOn

        width: 470
        height: 72
        radius: 36

        anchors.centerIn: tube

        color: root.glowColor
        opacity: 0.2
    }

    Rectangle {
        visible: root.isOn

        width: 530
        height: 100
        radius: 50

        anchors.centerIn: tube

        color: root.glowColor
        opacity: 0.12
    }

    Rectangle {
        id: tube

        width: 460
        height: 52
        radius: 26

        anchors.centerIn: parent

        gradient: Gradient {
            GradientStop { position: 0.0; color: "#fffdf5" }
            GradientStop { position: 0.45; color: "#ffffff" }
            GradientStop { position: 1.0; color: "#efe6cf" }
        }

        border.color: "#d8d0bd"
        border.width: 1
    }

    Rectangle {
        visible: root.isOn

        width: 420
        height: 16
        radius: 8

        anchors.centerIn: tube

        color: "#ffffff"
        opacity: 0.85
    }

    Rectangle {
        id: leftCap

        width: 56
        height: 66
        radius: 15

        anchors.verticalCenter: tube.verticalCenter
        anchors.right: tube.left
        anchors.rightMargin: -6

        gradient: Gradient {
            GradientStop { position: 0.0; color: "#f4f4f4" }
            GradientStop { position: 0.5; color: "#d8d8d8" }
            GradientStop { position: 1.0; color: "#bfbfbf" }
        }

        border.color: "#aaaaaa"
        border.width: 1
    }

    Rectangle {
        id: rightCap

        width: 56
        height: 66
        radius: 15

        anchors.verticalCenter: tube.verticalCenter
        anchors.left: tube.right
        anchors.leftMargin: -6

        gradient: Gradient {
            GradientStop { position: 0.0; color: "#f4f4f4" }
            GradientStop { position: 0.5; color: "#d8d8d8" }
            GradientStop { position: 1.0; color: "#bfbfbf" }
        }

        border.color: "#aaaaaa"
        border.width: 1
    }

    Rectangle {
        width: 24
        height: 6
        radius: 3
        color: "#707070"
        anchors.right: leftCap.left
        anchors.rightMargin: 0
        anchors.verticalCenter: leftCap.verticalCenter
        anchors.verticalCenterOffset: -14
    }

    Rectangle {
        width: 24
        height: 6
        radius: 3
        color: "#707070"
        anchors.right: leftCap.left
        anchors.rightMargin: 0
        anchors.verticalCenter: leftCap.verticalCenter
        anchors.verticalCenterOffset: 14
    }

    Rectangle {
        width: 24
        height: 6
        radius: 3
        color: "#707070"
        anchors.left: rightCap.right
        anchors.leftMargin: 0
        anchors.verticalCenter: rightCap.verticalCenter
        anchors.verticalCenterOffset: -14
    }

    Rectangle {
        width: 24
        height: 6
        radius: 3
        color: "#707070"
        anchors.left: rightCap.right
        anchors.leftMargin: 0
        anchors.verticalCenter: rightCap.verticalCenter
        anchors.verticalCenterOffset: 14
    }

    Rectangle {
        width: 2
        height: 58
        radius: 1
        color: "#c2c2c2"
        anchors.right: leftCap.right
        anchors.rightMargin: 8
        anchors.verticalCenter: leftCap.verticalCenter
    }

    Rectangle {
        width: 2
        height: 58
        radius: 1
        color: "#c2c2c2"
        anchors.left: rightCap.left
        anchors.leftMargin: 8
        anchors.verticalCenter: rightCap.verticalCenter
    }
}
