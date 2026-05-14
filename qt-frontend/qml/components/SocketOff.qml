import QtQuick

Item {
    id: root

    width: 260
    height: 380

    property color offColor: "#8f8f8f"

    Rectangle {
        anchors.fill: body
        anchors.topMargin: 10
        radius: 48
        color: "#000000"
        opacity: 0.12
    }

    Rectangle {
        id: body

        width: 220
        height: 340
        radius: 52
        anchors.centerIn: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#ffffff" }
            GradientStop { position: 0.55; color: "#f2f2f2" }
            GradientStop { position: 1.0; color: "#dddddd" }
        }
        border.color: "#bdbdbd"
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
        opacity: 0.75
    }

    Canvas {
        width: 60
        height: 38
        anchors.horizontalCenter: body.horizontalCenter
        anchors.top: body.top
        anchors.topMargin: 42

        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.strokeStyle = root.offColor
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
            ctx.fillStyle = root.offColor
            ctx.beginPath()
            ctx.arc(width / 2, 32, 4, 0, Math.PI * 2)
            ctx.fill()
        }
    }

    Rectangle {
        id: powerButton

        width: 64
        height: 64
        radius: 32
        anchors.horizontalCenter: body.horizontalCenter
        anchors.top: body.top
        anchors.topMargin: 92
        color: "#f8f8f8"
        border.width: 4
        border.color: root.offColor

        Text {
            anchors.centerIn: parent
            text: "⏻"
            color: "#777777"
            font.pixelSize: 36
            font.bold: true
        }
    }

    Rectangle {
        anchors.fill: powerButton
        radius: 32
        color: "transparent"
        border.color: "#ffffff"
        border.width: 2
        opacity: 0.45
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
        border.color: "#d5d5d5"
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
            GradientStop { position: 0.55; color: "#eeeeee" }
            GradientStop { position: 1.0; color: "#b9b9b9" }
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
        color: "#252525"
        border.color: "#f7f7f7"
        border.width: 3
    }

    Rectangle {
        width: 28
        height: 28
        radius: 14
        anchors.centerIn: socketBowl
        anchors.horizontalCenterOffset: 38
        color: "#252525"
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
