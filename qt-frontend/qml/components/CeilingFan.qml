import QtQuick

Item {
    id: root

    width: 500
    height: 500

    property bool isOn: false
    property int speedPercent: 60
    property bool speedControlEnabled: true
    property color accentColor: "#65e0b5"
    property color bladeColor: "#111717"
    property color bladeShadeColor: "#1f3d3a"
    property color engineColor: "#2f423f"
    property color centerColor: "#d7fffb"
    property color centerShadeColor: "#7f918d"
    readonly property int speedLevel: Math.max(1, Math.min(4, Math.round(Math.max(0, Math.min(100, speedPercent)) / 25)))
    property int animationDuration: Math.max(220, 1300 - Math.round(Math.max(0, Math.min(100, speedPercent)) * 9))

    signal toggled()
    signal speedChanged(int percentage)

    Item {
        id: head

        width: 300
        height: 300
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 0

        Rectangle {
            id: engine

            width: 100
            height: 100
            radius: 50
            x: 100
            y: 100
            color: root.engineColor
            border.color: "#45635d"
            border.width: 2

            Rectangle {
                width: 52
                height: 52
                radius: 26
                anchors.centerIn: parent
                color: "#21312e"
                border.color: root.accentColor
                border.width: root.isOn ? 2 : 1
                opacity: root.isOn ? 1 : 0.72
            }
        }

        Item {
            id: fanBlades

            width: 220
            height: 220
            x: 40
            y: 39
            transformOrigin: Item.Center

            RotationAnimator on rotation {
                running: root.isOn
                from: 0
                to: 360
                duration: root.animationDuration
                loops: Animation.Infinite
            }

            Repeater {
                model: 4

                Item {
                    width: 40
                    height: fanBlades.height
                    x: fanBlades.width / 2 - width / 2
                    y: 0
                    rotation: index * 90
                    transformOrigin: Item.Center

                    Rectangle {
                        width: parent.width
                        height: parent.height * 1.72
                        radius: 22
                        x: 0
                        y: -66
                        color: root.bladeColor
                        border.color: "#0d0d0d"
                        border.width: 1
                        opacity: root.isOn ? 0.92 : 0.78

                        transform: [
                            Rotation {
                                origin.x: 20
                                origin.y: 100
                                axis.x: 1
                                axis.y: 0
                                axis.z: 0
                                angle: 78
                            }
                        ]

                        Rectangle {
                            width: parent.width / 2
                            height: parent.height
                            radius: parent.radius
                            color: root.bladeShadeColor
                        }
                    }
                }
            }

            Rectangle {
                width: 40
                height: 40
                radius: 20
                anchors.centerIn: parent
                rotation: 45
                color: root.centerColor
                z: 2
                clip: true

                Rectangle {
                    width: parent.width
                    height: parent.height / 2
                    color: root.centerShadeColor
                }
            }
        }
    }

    Item {
        id: speedControls

        width: 500
        height: 92
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: head.bottom
        anchors.topMargin: 54
        visible: root.speedControlEnabled

        function setLevel(level) {
            root.speedChanged(Math.max(1, Math.min(4, level)) * 25)
        }

        Row {
            anchors.centerIn: parent
            spacing: 34

            SpeedButton {
                text: "-"
                enabled: root.speedLevel > 1
                onClicked: speedControls.setLevel(root.speedLevel - 1)
            }

            Item {
                width: 116
                height: 64

                Row {
                    anchors.centerIn: parent
                    spacing: 8

                    Repeater {
                        model: 4

                        Rectangle {
                            width: 16
                            height: 18 + (index * 10)
                            radius: 8
                            anchors.bottom: parent.bottom
                            color: index < root.speedLevel ? root.accentColor : "#303636"
                            border.color: index < root.speedLevel ? "#8af5d1" : "#4a5350"
                            border.width: 1
                            opacity: index < root.speedLevel ? 1 : 0.72
                        }
                    }
                }
            }

            SpeedButton {
                text: "+"
                enabled: root.speedLevel < 4
                onClicked: speedControls.setLevel(root.speedLevel + 1)
            }
        }
    }

    MouseArea {
        anchors.left: head.left
        anchors.right: head.right
        anchors.top: head.top
        anchors.bottom: head.bottom
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }

    component SpeedButton: Item {
        id: buttonRoot

        width: 62
        height: 62

        property string text: ""
        property bool enabled: true
        signal clicked()

        opacity: enabled ? 1 : 0.42

        Rectangle {
            width: parent.width
            height: parent.height
            x: 5
            y: 5
            radius: 18
            color: "#171717"
            opacity: 0.92
        }

        Rectangle {
            width: parent.width
            height: parent.height
            x: -5
            y: -5
            radius: 18
            color: "#3d3d3d"
            opacity: 0.55
        }

        Rectangle {
            anchors.fill: parent
            radius: 18
            color: "#212121"
            border.color: mouseArea.pressed && buttonRoot.enabled ? root.accentColor : "#2c3532"
            border.width: 1

            Text {
                anchors.centerIn: parent
                text: buttonRoot.text
                color: root.centerColor
                font.pixelSize: 32
                font.bold: true
            }
        }

        MouseArea {
            id: mouseArea

            anchors.fill: parent
            enabled: buttonRoot.enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: buttonRoot.clicked()
        }
    }
}
