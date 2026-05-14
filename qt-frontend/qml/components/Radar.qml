import QtQuick

Item {
    id: radar

    width: 400
    height: 400
    clip: false

    Repeater {
        model: 8

        Rectangle {
            readonly property real circleSize: (index + 1) * 80
            readonly property var ringColors: [
                Qt.rgba(228 / 255, 228 / 255, 231 / 255, 0.48),
                Qt.rgba(228 / 255, 228 / 255, 231 / 255, 0.42),
                Qt.rgba(212 / 255, 212 / 255, 216 / 255, 0.36),
                Qt.rgba(212 / 255, 212 / 255, 216 / 255, 0.30),
                Qt.rgba(161 / 255, 161 / 255, 170 / 255, 0.25),
                Qt.rgba(161 / 255, 161 / 255, 170 / 255, 0.20),
                Qt.rgba(161 / 255, 161 / 255, 170 / 255, 0.15),
                Qt.rgba(161 / 255, 161 / 255, 170 / 255, 0.10)
            ]

            width: circleSize
            height: circleSize
            radius: width / 2
            anchors.centerIn: parent
            color: "transparent"
            border.width: 1
            border.color: ringColors[index]
        }
    }

    Item {
        id: sweep

        anchors.fill: parent
        rotation: 20
        transformOrigin: Item.Center

        Rectangle {
            width: parent.width * 0.9
            height: 1
            x: parent.width / 2 - 6
            anchors.verticalCenter: parent.verticalCenter
            color: "#5D81FF"
            opacity: 0.9
        }

        Rectangle {
            width: 6
            height: 6
            radius: 3
            anchors.centerIn: parent
            color: "#bae6fd"
            opacity: 0.9
        }

        RotationAnimator {
            target: sweep
            from: 20
            to: 380
            duration: 10000
            loops: Animation.Infinite
            running: true
        }
    }
}
