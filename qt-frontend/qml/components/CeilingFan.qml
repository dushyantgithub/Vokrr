import QtQuick

Item {
    id: root

    width: 520
    height: 420

    property bool spinning: false
    property int speed: 2200
    property color fanColor: "#f5f5f5"
    property color edgeColor: "#c9c9c9"
    property color metalColor: "#9f9f9f"

    Rectangle {
        width: 86
        height: 44
        radius: 22
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 20
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#ffffff" }
            GradientStop { position: 1.0; color: "#dcdcdc" }
        }
        border.color: edgeColor
    }

    Rectangle {
        width: 18
        height: 88
        radius: 9
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 58
        color: "#f1f1f1"
        border.color: edgeColor
    }

    Item {
        id: rotor
        width: 460
        height: 300
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 120
        transformOrigin: Item.Center

        RotationAnimator on rotation {
            running: root.spinning
            from: 0
            to: 360
            duration: root.speed
            loops: Animation.Infinite
        }

        Rectangle {
            width: 245
            height: 52
            radius: 20
            x: 5
            y: 52
            rotation: -28
            color: root.fanColor
            border.color: root.edgeColor

            Rectangle {
                anchors.fill: parent
                anchors.margins: 8
                radius: 16
                color: "transparent"
                border.color: "#ffffff"
                opacity: 0.65
            }
        }

        Rectangle {
            width: 245
            height: 52
            radius: 20
            x: 213
            y: 52
            rotation: 28
            color: root.fanColor
            border.color: root.edgeColor

            Rectangle {
                anchors.fill: parent
                anchors.margins: 8
                radius: 16
                color: "transparent"
                border.color: "#ffffff"
                opacity: 0.65
            }
        }

        Rectangle {
            width: 58
            height: 190
            radius: 18
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 112
            color: root.fanColor
            border.color: root.edgeColor

            Rectangle {
                anchors.fill: parent
                anchors.margins: 8
                radius: 14
                color: "transparent"
                border.color: "#ffffff"
                opacity: 0.65
            }
        }

        Rectangle {
            width: 62
            height: 26
            radius: 12
            x: 140
            y: 128
            rotation: -28
            color: "#d8d8d8"
            border.color: root.metalColor
        }

        Rectangle {
            width: 62
            height: 26
            radius: 12
            x: 258
            y: 128
            rotation: 28
            color: "#d8d8d8"
            border.color: root.metalColor
        }

        Rectangle {
            width: 36
            height: 54
            radius: 14
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 156
            color: "#d8d8d8"
            border.color: root.metalColor
        }

        Rectangle {
            width: 132
            height: 92
            radius: 46
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 104
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#ffffff" }
                GradientStop { position: 0.55; color: "#eeeeee" }
                GradientStop { position: 1.0; color: "#cfcfcf" }
            }
            border.color: root.edgeColor
            border.width: 2
        }

        Rectangle {
            width: 108
            height: 74
            radius: 37
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 116
            color: "#f6f6f6"
            border.color: "#bdbdbd"
            border.width: 2
        }

        Rectangle {
            width: 120
            height: 5
            radius: 2
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 124
            color: "#9d9d9d"
            opacity: 0.7
        }
    }
}
