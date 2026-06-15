import QtQuick
import QtQuick.Effects

Item {
    id: root

    property var theme
    property string deviceName: ""
    property string meta: ""
    property string statusText: ""
    property string deviceType: "switch"
    property bool deviceActive: false
    property bool actionable: false
    property bool hasLevel: false
    property real levelValue: 0
    property var rawDevice: null
    signal activated(var rawDevice)
    signal levelRequested(var rawDevice, real value)

    width: 156
    height: 128

    readonly property real cardRadius: theme ? theme.radiusXl : 28
    readonly property color accent: theme ? theme.accentForType(root.deviceType, true) : "#5AC8FA"
    readonly property bool pressed: cardTap.pressed
    readonly property real displayLevel: Math.max(0, Math.min(100, levelDrag.dragging ? levelDrag.previewValue : root.levelValue))

    scale: pressed ? 0.972 : 1
    opacity: actionable ? 1 : 0.72

    Behavior on scale {
        NumberAnimation { duration: 115; easing.type: Easing.OutCubic }
    }

    Rectangle {
        id: shadowShape
        anchors.fill: parent
        anchors.margins: 2
        radius: root.cardRadius
        color: root.deviceActive ? root.accent : (theme ? theme.bgSurface : "#FFFFFF")
    }

    MultiEffect {
        anchors.fill: shadowShape
        source: shadowShape
        autoPaddingEnabled: true
        shadowEnabled: true
        shadowColor: root.deviceActive ? root.accent : (theme ? theme.shadow : "#26000000")
        shadowOpacity: root.deviceActive ? 0.28 : 0.18
        shadowBlur: root.deviceActive ? 0.72 : 0.42
        shadowVerticalOffset: root.deviceActive ? 9 : 7
        shadowHorizontalOffset: 0
    }

    Rectangle {
        id: face
        anchors.fill: parent
        radius: root.cardRadius
        border.width: 1
        border.color: root.deviceActive ? root.accent : (theme ? theme.borderSubtle : "#D9DCE3")
        clip: true

        gradient: Gradient {
            GradientStop {
                position: 0
                color: root.deviceActive ? root.activeTopColor() : (theme ? theme.cardTop : "#FFFFFF")
            }
            GradientStop {
                position: 1
                color: root.deviceActive ? root.activeBottomColor() : (theme ? theme.cardBottom : "#EDEFF4")
            }
        }

        Behavior on border.color {
            ColorAnimation { duration: 180 }
        }
    }

    Rectangle {
        anchors.fill: face
        radius: face.radius
        color: theme ? theme.pressFill : "#1F000000"
        opacity: root.pressed ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: 110; easing.type: Easing.OutQuad }
        }
    }

    Rectangle {
        x: 14
        y: 14
        width: 42
        height: 42
        radius: 16
        color: root.deviceActive ? root.iconBubbleColor() : (theme ? theme.bgSurfaceSoft : "#ECEEF3")
        border.width: root.deviceActive ? 0 : 1
        border.color: theme ? theme.borderSubtle : "#D9DCE3"

        Behavior on color {
            ColorAnimation { duration: 180 }
        }

        SvgIcon {
            anchors.centerIn: parent
            width: 23
            height: 23
            name: root.iconForType(root.deviceType)
            iconColor: theme ? theme.iconColor : "#1D1D1F"
            darkMode: theme ? theme.darkMode : false
        }
    }

    Column {
        x: 66
        y: 16
        width: parent.width - 80
        spacing: 1

        Text {
            width: parent.width
            text: root.deviceName
            color: theme ? theme.textPrimary : "#1D1D1F"
            font.family: theme ? theme.family() : "Inter"
            font.pixelSize: 14
            font.bold: true
            elide: Text.ElideRight
        }

        Text {
            width: parent.width
            text: root.meta
            color: theme ? theme.textMuted : "#6E6E73"
            font.family: theme ? theme.family() : "Inter"
            font.pixelSize: 10
            elide: Text.ElideRight
        }
    }

    Rectangle {
        x: 14
        y: root.hasLevel ? parent.height - 54 : parent.height - 42
        width: Math.min(parent.width - 76, Math.max(54, statusLabel.implicitWidth + 18))
        height: 24
        radius: 999
        color: root.deviceActive ? root.statusPillColor() : (theme ? theme.bgSurfaceSoft : "#ECEEF3")
        border.width: root.deviceActive ? 0 : 1
        border.color: theme ? theme.borderSubtle : "#D9DCE3"

        Behavior on color {
            ColorAnimation { duration: 180 }
        }

        Text {
            id: statusLabel
            anchors.centerIn: parent
            width: parent.width - 12
            text: root.statusText
            color: root.deviceActive ? root.accent : (theme ? theme.textSecondary : "#3A3A3C")
            font.family: theme ? theme.family() : "Inter"
            font.pixelSize: 10
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
    }

    Rectangle {
        id: toggleTrack
        x: parent.width - width - 14
        y: root.hasLevel ? parent.height - 54 : parent.height - 42
        width: 46
        height: 24
        radius: 999
        color: root.deviceActive ? root.accent : (theme ? theme.bgSurfaceSoft : "#ECEEF3")
        border.width: root.deviceActive ? 0 : 1
        border.color: theme ? theme.borderSubtle : "#D9DCE3"

        Behavior on color {
            ColorAnimation { duration: 180 }
        }

        Rectangle {
            width: 18
            height: 18
            radius: 9
            y: 3
            x: root.deviceActive ? parent.width - width - 3 : 3
            color: theme && theme.darkMode ? "#F5F5F7" : "#FFFFFF"

            Behavior on x {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            enabled: root.actionable
            onClicked: root.activate()
        }
    }

    Rectangle {
        id: levelTrack
        x: 14
        y: parent.height - 18
        width: parent.width - 28
        height: 5
        radius: 999
        visible: root.hasLevel
        color: theme ? theme.bgSurfaceSoft : "#ECEEF3"

        Rectangle {
            width: parent.width * (root.displayLevel / 100)
            height: parent.height
            radius: parent.radius
            color: root.accent

            Behavior on width {
                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
            }
        }

        MouseArea {
            id: levelDrag
            anchors.fill: parent
            anchors.margins: -8
            cursorShape: Qt.PointingHandCursor
            property bool dragging: false
            property real previewValue: root.levelValue

            function valueFor(mouseX) {
                return Math.max(0, Math.min(100, (mouseX - 8) / Math.max(1, levelTrack.width) * 100))
            }

            onPressed: function(mouse) {
                dragging = true
                previewValue = valueFor(mouse.x)
            }
            onPositionChanged: function(mouse) {
                if (dragging)
                    previewValue = valueFor(mouse.x)
            }
            onReleased: {
                dragging = false
                root.levelRequested(root.rawDevice, Math.round(previewValue))
            }
            onCanceled: dragging = false
        }
    }

    MouseArea {
        id: cardTap
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        enabled: root.actionable
        z: -1
        onClicked: root.activate()
    }

    function activate() {
        if (root.actionable)
            root.activated(root.rawDevice)
    }

    function activeTopColor() {
        if (!theme)
            return "#FFFFFF"
        if (theme.darkMode)
            return root.deviceType === "light" ? "#3D3515" : "#263139"
        return root.deviceType === "light" ? "#FFFFF3D0" : "#FFFFFFFF"
    }

    function activeBottomColor() {
        if (!theme)
            return "#F4F7FF"
        if (theme.darkMode)
            return root.deviceType === "light" ? "#24200F" : "#1A2226"
        return root.deviceType === "light" ? "#FFFFFAE8" : "#FFF2F8FF"
    }

    function iconBubbleColor() {
        if (!theme)
            return "#ECEEF3"
        return theme.darkMode ? "#1AFFFFFF" : "#CCFFFFFF"
    }

    function statusPillColor() {
        if (!theme)
            return "#ECEEF3"
        return theme.darkMode ? "#1AFFFFFF" : "#D9FFFFFF"
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
        if (value === "plug")
            return "plug"
        return "toggle-left"
    }
}
