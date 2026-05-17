import QtQuick
import QtQuick.Effects

GlassPanel {
    id: root

    property string roomName: "Room"
    property string roomImageSource: "qrc:/assets/images/room-1.jpg"
    property var devices: []

    width: 356
    height: 214
    radius: theme.radiusXl
    padding: 0
    clip: true

    Rectangle {
        id: heroMask

        anchors.fill: parent
        radius: root.radius
        visible: false
        layer.enabled: true
    }

    Item {
        anchors.fill: parent
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: heroMask
        }

        Image {
            anchors.fill: parent
            source: root.roomImageSource
            fillMode: Image.PreserveAspectCrop
            opacity: theme.darkMode ? 0.42 : 0.72
            smooth: true
            asynchronous: true
        }

        Rectangle {
            anchors.fill: parent
            color: theme.darkMode ? theme.bgOverlay : "#14000000"
        }
    }

    Row {
        x: theme.space6
        y: theme.space6
        width: parent.width - theme.space6 * 2
        spacing: theme.space4
        clip: true
        Repeater {
            model: [
                { icon: "lightbulb", label: "Lights", value: countActive("light") },
                { icon: "fan", label: "Fans", value: countActive("fan") },
                { icon: "toggle-left", label: "Switch", value: countActive("switch") }
            ]
            Item {
                width: Math.max(86, (parent.width - theme.space4 * 2) / 3)
                height: 42
                SvgIcon {
                    x: 0
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18
                    height: 18
                    name: modelData.icon
                    iconColor: theme.iconColor
                    darkMode: theme.darkMode
                }
                Text {
                    x: 26
                    y: 1
                    width: parent.width - 26
                    text: modelData.label
                    color: theme.textPrimary
                    font.family: theme.family()
                    font.pixelSize: theme.bodySm
                    font.bold: true
                    elide: Text.ElideRight
                }
                Text {
                    x: 26
                    y: 19
                    width: parent.width - 26
                    text: modelData.value + " active"
                    color: theme.accentCyanSoft
                    font.family: theme.family()
                    font.pixelSize: theme.caption
                    font.bold: true
                    elide: Text.ElideRight
                }
            }
        }
    }

    Text {
        x: theme.space6
        y: Math.max(88, parent.height - 86)
        width: parent.width - theme.space6 * 2
        text: root.roomName
        color: theme.textPrimary
        font.family: theme.family()
        font.pixelSize: theme.displaySm
        font.bold: true
        elide: Text.ElideRight
    }

    Text {
        x: theme.space6
        y: Math.max(120, parent.height - 50)
        width: parent.width - theme.space6 * 2
        text: devices.length + " area devices • live controls"
        color: theme.textSecondary
        font.family: theme.family()
        font.pixelSize: theme.bodyMd
        elide: Text.ElideRight
    }

    function countActive(typeName) {
        var count = 0
        for (var i = 0; i < devices.length; i++) {
            if (devices[i].type === typeName && devices[i].active)
                count++
        }
        return count
    }
}
