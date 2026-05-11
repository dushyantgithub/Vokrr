import QtQuick
import QtQuick.Controls

Rectangle {
    id: root

    property string deviceName: "Device"
    property string deviceType: "light"
    property bool deviceOn: false

    signal toggled(bool enabled)

    width: 156
    height: 104
    radius: 8
    color: deviceOn ? "#143d3b" : "#151b24"
    border.color: deviceOn ? "#33e0c2" : "#263342"
    border.width: 1
    scale: pressArea.pressed ? 0.97 : 1.0

    Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
    Behavior on color { ColorAnimation { duration: 160 } }
    Behavior on border.color { ColorAnimation { duration: 160 } }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: 7
        gradient: Gradient {
            GradientStop { position: 0.0; color: deviceOn ? "#1d5952" : "#1e2630" }
            GradientStop { position: 1.0; color: deviceOn ? "#123331" : "#10151d" }
        }
        opacity: 0.86
    }

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        spacing: 5

        Text {
            width: parent.width
            text: root.deviceName
            color: "#f4fbff"
            font.pixelSize: 16
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }

        Text {
            width: parent.width
            text: root.deviceType
            color: "#8fa1b5"
            font.pixelSize: 11
            elide: Text.ElideRight
        }
    }

    Rectangle {
        id: toggle
        width: 58
        height: 32
        radius: 16
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 12
        color: root.deviceOn ? "#26f0ce" : "#25303e"
        border.color: root.deviceOn ? "#99fff0" : "#3b4b5f"

        Behavior on color { ColorAnimation { duration: 160 } }

        Rectangle {
            width: 24
            height: 24
            radius: 12
            y: 4
            x: root.deviceOn ? 30 : 4
            color: root.deviceOn ? "#06211f" : "#d8e3ee"
            Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        }
    }

    Text {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 12
        text: root.deviceOn ? "ON" : "OFF"
        color: root.deviceOn ? "#8ffff0" : "#718196"
        font.pixelSize: 12
        font.weight: Font.Bold
    }

    MouseArea {
        id: pressArea
        anchors.fill: parent
        onClicked: {
            root.deviceOn = !root.deviceOn
            root.toggled(root.deviceOn)
        }
    }
}
