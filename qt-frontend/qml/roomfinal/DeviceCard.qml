import QtQuick
import "../components" as VokrrComponents

GlassPanel {
    id: root

    property string deviceName: ""
    property string meta: ""
    property string statusText: ""
    property string deviceType: "switch"
    property bool deviceActive: false
    property bool actionable: false
    property var rawDevice: null
    signal activated(var rawDevice)

    width: 166
    height: 54
    radius: theme.radiusLg - 2
    padding: theme.space5
    active: deviceActive

    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutQuad } }

    function activatePowerButton() {
        if (root.actionable)
            root.activated(root.rawDevice)
    }

    SvgIcon {
        x: 0
        y: 5
        width: 24
        height: 24
        name: iconForType(deviceType)
        iconColor: theme.iconColor
        darkMode: theme.darkMode
    }

    Column {
        x: 32
        y: 0
        width: parent.width - 70
        spacing: 0
        Text {
            width: parent.width
            text: root.deviceName
            color: theme.textPrimary
            font.family: theme.family()
            font.pixelSize: theme.bodyMd
            font.bold: true
            elide: Text.ElideRight
        }
        Text {
            width: parent.width
            text: root.meta
            color: theme.textMuted
            font.family: theme.family()
            font.pixelSize: theme.caption
            elide: Text.ElideRight
        }
        Text {
            width: parent.width
            text: root.statusText
            color: theme.accentForType(root.deviceType, root.deviceActive)
            font.family: theme.family()
            font.pixelSize: theme.caption
            font.bold: true
            elide: Text.ElideRight
        }
    }

    VokrrComponents.Button {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 32
        height: 32
        variant: "ghost"
        darkMode: theme.darkMode
        selected: root.deviceActive
        SvgIcon {
            anchors.centerIn: parent
            width: 18
            height: 18
            name: "power"
            iconColor: theme.iconColor
            darkMode: theme.darkMode
        }
        onClicked: root.activatePowerButton()
    }

    function iconForType(typeName) {
        var value = String(typeName).toLowerCase()
        if (value === "light")
            return "lightbulb"
        if (value === "fan")
            return "fan"
        if (value === "ac")
            return "snowflake"
        if (value === "tv")
            return "tv"
        if (value === "camera")
            return "camera"
        if (value === "curtain")
            return "panels-top-left"
        if (value === "speaker")
            return "volume-2"
        if (value === "purifier")
            return "air-vent"
        if (value === "sensor")
            return "activity"
        return "toggle-left"
    }
}
