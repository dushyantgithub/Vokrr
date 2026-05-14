import QtQuick

Item {
    id: root

    width: 220
    height: 420

    Rectangle {
        width: 4
        height: 120
        radius: 2
        color: "#111111"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
    }

    Item {
        id: holder

        width: 90
        height: 100
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 108

        Column {
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 4

            Repeater {
                model: 4

                Rectangle {
                    width: 52 - index * 6
                    height: 8
                    radius: 4
                    color: "#1a1a1a"
                    border.color: "#2b2b2b"
                    border.width: 1
                }
            }
        }

        Rectangle {
            width: 74
            height: 72
            radius: 10
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            color: "#121212"
            border.color: "#2f2f2f"
            border.width: 2
        }

        Rectangle {
            width: 82
            height: 12
            radius: 6
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            color: "#1c1c1c"
            border.color: "#303030"
            border.width: 1
        }
    }

    Item {
        id: bulb

        width: 150
        height: 220
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: holder.bottom

        Rectangle {
            id: glass

            width: parent.width
            height: parent.height - 12
            radius: 75
            color: Qt.rgba(1, 1, 1, 0.05)
            border.width: 3
            border.color: Qt.rgba(1, 1, 1, 0.28)
        }

        Rectangle {
            width: 38
            height: 38
            radius: 19
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            color: Qt.rgba(1, 1, 1, 0.05)
            border.width: 3
            border.color: Qt.rgba(1, 1, 1, 0.28)
        }

        Rectangle {
            width: 20
            height: 120
            radius: 10
            anchors.left: parent.left
            anchors.leftMargin: 26
            anchors.top: parent.top
            anchors.topMargin: 26
            rotation: -7
            color: "#ffffff"
            opacity: 0.12
        }

        Rectangle {
            width: 3
            height: 112
            radius: 2
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 34
            color: "#8a8a8a"
        }

        Rectangle {
            width: 3
            height: 80
            radius: 2
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: -18
            anchors.top: parent.top
            anchors.topMargin: 74
            color: "#8a8a8a"
            rotation: -8
        }

        Rectangle {
            width: 3
            height: 80
            radius: 2
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: 18
            anchors.top: parent.top
            anchors.topMargin: 74
            color: "#8a8a8a"
            rotation: 8
        }

        Rectangle {
            width: 8
            height: 66
            radius: 4
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: -16
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 8
            color: "#D6A420"
        }

        Rectangle {
            width: 8
            height: 66
            radius: 4
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: 16
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 8
            color: "#D6A420"
        }

        Rectangle {
            width: 26
            height: 8
            radius: 4
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 48
            color: "#8f8f8f"
        }
    }

    SequentialAnimation on y {
        running: true
        loops: Animation.Infinite

        NumberAnimation {
            to: -3
            duration: 2400
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            to: 3
            duration: 2400
            easing.type: Easing.InOutSine
        }
    }
}
