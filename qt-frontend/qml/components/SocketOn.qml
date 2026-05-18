import QtQuick

Item {
    id: root

    width: 260
    height: 380

    property bool isOn: true
    property color accentColor: "#2578ff"

    Rectangle {
        anchors.fill: body
        anchors.topMargin: 10
        radius: 48
        color: "#000000"
        opacity: 0.14
    }

    Rectangle {
        id: body

        width: 220
        height: 340
        radius: 52
        anchors.centerIn: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#ffffff" }
            GradientStop { position: 0.55; color: "#f3f3f3" }
            GradientStop { position: 1.0; color: "#dddddd" }
        }
        border.color: "#c7c7c7"
        border.width: 2
    }

    Rectangle {
        width: 198
        height: 318
        radius: 46
        anchors.centerIn: body
        color: "transparent"
        border.color: "#ffffff"
        border.width: 2
        opacity: 0.8
    }

    Item {
        id: wifi

        width: 60
        height: 38
        anchors.horizontalCenter: body.horizontalCenter
        anchors.top: body.top
        anchors.topMargin: 42

        Canvas {
            anchors.fill: parent

            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                ctx.strokeStyle = root.accentColor
                ctx.lineWidth = 5
                ctx.lineCap = "round"
                ctx.beginPath()
                ctx.arc(width / 2, 32, 28, Math.PI * 1.22, Math.PI * 1.78)
                ctx.stroke()
                ctx.beginPath()
                ctx.arc(width / 2, 32, 18, Math.PI * 1.25, Math.PI * 1.75)
                ctx.stroke()
                ctx.beginPath()
                ctx.arc(width / 2, 32, 8, Math.PI * 1.30, Math.PI * 1.70)
                ctx.stroke()
                ctx.fillStyle = root.accentColor
                ctx.beginPath()
                ctx.arc(width / 2, 32, 4, 0, Math.PI * 2)
                ctx.fill()
            }
        }
    }

    Rectangle {
        visible: root.isOn
        width: 76
        height: 76
        radius: 38
        anchors.horizontalCenter: body.horizontalCenter
        anchors.top: body.top
        anchors.topMargin: 86
        color: root.accentColor
        opacity: 0.25
    }

    Rectangle {
        id: powerButton

        width: 64
        height: 64
        radius: 32
        anchors.horizontalCenter: body.horizontalCenter
        anchors.top: body.top
        anchors.topMargin: 92
        color: "#ffffff"
        border.width: 5
        border.color: root.isOn ? root.accentColor : "#9a9a9a"

        Text {
            anchors.centerIn: parent
            text: "⏻"
            color: root.isOn ? root.accentColor : "#9a9a9a"
            font.pixelSize: 38
            font.bold: true
        }
    }

    Rectangle {
        id: socketRing

        width: 176
        height: 176
        radius: 88
        anchors.horizontalCenter: body.horizontalCenter
        anchors.top: body.top
        anchors.topMargin: 180
        color: "#f4f4f4"
        border.color: "#d4d4d4"
        border.width: 4
    }

    Rectangle {
        id: socketBowl

        width: 150
        height: 150
        radius: 75
        anchors.centerIn: socketRing
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#c8c8c8" }
            GradientStop { position: 0.55; color: "#efefef" }
            GradientStop { position: 1.0; color: "#b8b8b8" }
        }
        border.color: "#9f9f9f"
        border.width: 2
    }

    Rectangle {
        width: 28
        height: 28
        radius: 14
        anchors.centerIn: socketBowl
        anchors.horizontalCenterOffset: -38
        color: "#222222"
        border.color: "#f7f7f7"
        border.width: 3
    }

    Rectangle {
        width: 28
        height: 28
        radius: 14
        anchors.centerIn: socketBowl
        anchors.horizontalCenterOffset: 38
        color: "#222222"
        border.color: "#f7f7f7"
        border.width: 3
    }

    Rectangle {
        width: 22
        height: 44
        radius: 5
        anchors.horizontalCenter: socketBowl.horizontalCenter
        anchors.top: socketBowl.top
        anchors.topMargin: 8
        color: "#111111"

        Rectangle {
            width: 10
            height: 34
            radius: 4
            anchors.centerIn: parent
            color: "#eeeeee"
            border.color: "#9a9a9a"
            border.width: 1
        }
    }

    Rectangle {
        width: 22
        height: 44
        radius: 5
        anchors.horizontalCenter: socketBowl.horizontalCenter
        anchors.bottom: socketBowl.bottom
        anchors.bottomMargin: 8
        color: "#111111"

        Rectangle {
            width: 10
            height: 34
            radius: 4
            anchors.centerIn: parent
            color: "#eeeeee"
            border.color: "#9a9a9a"
            border.width: 1
        }
    }

    Rectangle {
        width: 16
        height: 54
        radius: 8
        anchors.left: socketBowl.left
        anchors.leftMargin: 10
        anchors.verticalCenter: socketBowl.verticalCenter
        color: "#eeeeee"
        border.color: "#c3c3c3"
        border.width: 1
    }

    Rectangle {
        width: 16
        height: 54
        radius: 8
        anchors.right: socketBowl.right
        anchors.rightMargin: 10
        anchors.verticalCenter: socketBowl.verticalCenter
        color: "#eeeeee"
        border.color: "#c3c3c3"
        border.width: 1
    }
}
