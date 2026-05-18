import QtQuick

Item {
    id: root

    width: 220
    height: 420

    property color glowColor: "#FFD76A"
    property bool isOn: true

    Rectangle {
        width: 4
        height: 120
        radius: 2
        color: "#1a1a1a"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
    }

    Rectangle {
        id: holder

        width: 70
        height: 90
        radius: 16
        color: "#111111"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 110
        border.color: "#2d2d2d"
        border.width: 2

        Column {
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 6
            topPadding: 10

            Repeater {
                model: 4

                Rectangle {
                    width: 42 - index * 5
                    height: 5
                    radius: 3
                    color: "#2a2a2a"
                }
            }
        }
    }

    Rectangle {
        id: glow

        visible: root.isOn
        width: 150
        height: 220
        radius: 75
        color: root.glowColor
        opacity: 0.22
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: holder.bottom
        anchors.topMargin: 8
    }

    Item {
        id: bulb

        width: 120
        height: 200
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: holder.bottom
        anchors.topMargin: 10

        Rectangle {
            id: bulbGlass

            width: parent.width
            height: parent.height
            radius: 60
            color: Qt.rgba(1.0, 0.87, 0.45, 0.32)
            border.width: 3
            border.color: "#FFD76A"
        }

        Rectangle {
            width: 34
            height: 34
            radius: 17
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: -8
            color: bulbGlass.color
            border.width: 3
            border.color: bulbGlass.border.color
        }

        Rectangle {
            width: 18
            height: 90
            radius: 9
            color: "#ffffff"
            opacity: 0.18
            anchors.left: parent.left
            anchors.leftMargin: 22
            anchors.top: parent.top
            anchors.topMargin: 28
            rotation: -8
        }

        Rectangle {
            width: 3
            height: 90
            radius: 2
            color: "#C69214"
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 45
        }

        Rectangle {
            width: 3
            height: 90
            radius: 2
            color: "#C69214"
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: -16
            anchors.top: parent.top
            anchors.topMargin: 65
        }

        Rectangle {
            width: 3
            height: 90
            radius: 2
            color: "#C69214"
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: 16
            anchors.top: parent.top
            anchors.topMargin: 65
        }

        Rectangle {
            width: 10
            height: 70
            radius: 5
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: -16
            anchors.verticalCenter: parent.verticalCenter
            color: "#FFF7B0"
        }

        Rectangle {
            width: 10
            height: 70
            radius: 5
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: 16
            anchors.verticalCenter: parent.verticalCenter
            color: "#FFF7B0"
        }
    }

    SequentialAnimation on y {
        running: true
        loops: Animation.Infinite

        NumberAnimation {
            to: -4
            duration: 2200
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            to: 4
            duration: 2200
            easing.type: Easing.InOutSine
        }
    }

    SequentialAnimation {
        running: true
        loops: Animation.Infinite

        NumberAnimation {
            target: glow
            property: "opacity"
            to: 0.18
            duration: 120
        }

        NumberAnimation {
            target: glow
            property: "opacity"
            to: 0.24
            duration: 180
        }

        PauseAnimation {
            duration: 2400
        }
    }
}
