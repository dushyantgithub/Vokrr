import QtQuick

Item {
    id: root

    width: 560
    height: 140

    property color lightColor: "#fff2c7"
    property real glowOpacity: 0.55
    property color tubeColor: Qt.rgba(
        Math.max(root.lightColor.r, 0.22),
        Math.max(root.lightColor.g, 0.22),
        Math.max(root.lightColor.b, 0.22),
        1
    )

    Rectangle {
        id: outerGlow

        width: 470
        height: 72
        radius: 36

        anchors.centerIn: tube

        color: root.lightColor
        opacity: root.glowOpacity * 0.45
    }

    Rectangle {
        width: 530
        height: 100
        radius: 50

        anchors.centerIn: tube

        color: root.lightColor
        opacity: root.glowOpacity * 0.22
    }

    Rectangle {
        id: tube

        width: 460
        height: 52
        radius: 26

        anchors.centerIn: parent

        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: Qt.lighter(root.tubeColor, 1.25)
            }

            GradientStop {
                position: 0.45
                color: Qt.lighter(root.tubeColor, 1.08)
            }

            GradientStop {
                position: 1.0
                color: Qt.darker(root.tubeColor, 1.08)
            }
        }

        border.color: Qt.darker(root.tubeColor, 1.35)
        border.width: 1
    }

    Rectangle {
        width: 420
        height: 16
        radius: 8

        anchors.centerIn: tube

        color: Qt.lighter(root.tubeColor, 1.35)
        opacity: 0.82
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
            GradientStop { position: 0.0; color: "#f7f7f7" }
            GradientStop { position: 0.5; color: "#d7d7d7" }
            GradientStop { position: 1.0; color: "#bfbfbf" }
        }

        border.color: "#ababab"
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
            GradientStop { position: 0.0; color: "#f7f7f7" }
            GradientStop { position: 0.5; color: "#d7d7d7" }
            GradientStop { position: 1.0; color: "#bfbfbf" }
        }

        border.color: "#ababab"
        border.width: 1
    }

    Rectangle {
        width: 24
        height: 6
        radius: 3

        anchors.right: leftCap.left
        anchors.verticalCenter: leftCap.verticalCenter
        anchors.verticalCenterOffset: -14

        color: "#666666"
    }

    Rectangle {
        width: 24
        height: 6
        radius: 3

        anchors.right: leftCap.left
        anchors.verticalCenter: leftCap.verticalCenter
        anchors.verticalCenterOffset: 14

        color: "#666666"
    }

    Rectangle {
        width: 24
        height: 6
        radius: 3

        anchors.left: rightCap.right
        anchors.verticalCenter: rightCap.verticalCenter
        anchors.verticalCenterOffset: -14

        color: "#666666"
    }

    Rectangle {
        width: 24
        height: 6
        radius: 3

        anchors.left: rightCap.right
        anchors.verticalCenter: rightCap.verticalCenter
        anchors.verticalCenterOffset: 14

        color: "#666666"
    }

    Rectangle {
        width: 2
        height: 58
        radius: 1

        anchors.right: leftCap.right
        anchors.rightMargin: 8
        anchors.verticalCenter: leftCap.verticalCenter

        color: "#c7c7c7"
    }

    Rectangle {
        width: 2
        height: 58
        radius: 1

        anchors.left: rightCap.left
        anchors.leftMargin: 8
        anchors.verticalCenter: rightCap.verticalCenter

        color: "#c7c7c7"
    }

    SequentialAnimation on opacity {
        running: true
        loops: Animation.Infinite

        NumberAnimation {
            to: 0.97
            duration: 120
        }

        NumberAnimation {
            to: 1.0
            duration: 160
        }

        PauseAnimation {
            duration: 2600
        }
    }
}
