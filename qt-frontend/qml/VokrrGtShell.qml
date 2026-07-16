pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

Item {
    id: root
    objectName: "vokrrShell"
    clip: true
    focus: true

    property var rooms: []
    property var scenes: []
    property var health: null
    property string healthError: ""
    property bool healthLoading: false
    property int healthRangeDays: 1
    property bool backendOnline: false
    property bool authenticated: false
    property bool realtimeConnected: false
    property string userName: "Dushyant"
    property string apiBase: "http://localhost:8080"
    property var systemInfo: ({})
    property string assistantStatus: "idle"
    property string assistantMessage: "waiting for wake-word"
    property bool voicePipelineActive: false
    property bool wakeWordEnabled: true
    property string themeMode: "AUTO"
    property bool reducedMotion: false

    property string currentScreen: "dashboard"
    property string selectedRoomId: ""
    property var selectedColorDevice: null
    property real paletteBrightness: 100
    property string clockText: ""
    property string dateText: ""

    readonly property color backgroundTop: "#0a0d0c"
    readonly property color backgroundBase: "#060807"
    readonly property color backgroundBottom: "#081210"
    readonly property color textPrimary: "#eef2ef"
    readonly property color textSecondary: "#c6cdc9"
    readonly property color textMuted: "#8a9691"
    readonly property color textDim: "#5f6b66"
    readonly property color accentGreen: "#2ec79a"
    readonly property color accentGold: "#d9cba8"
    readonly property color inactive: "#3c4642"
    readonly property string displayFont: "Jost"
    readonly property string monoFont: "IBM Plex Mono"
    readonly property int transitionDuration: reducedMotion ? 0 : 180
    readonly property real surfaceScale: Math.min(width / 800, height / 480)

    signal deviceToggleRequested(var device)
    signal deviceSetRequested(var device, var payload)
    signal roomSetRequested(var room, bool state)
    signal healthRangeRequested(int days)
    signal healthRefreshRequested()
    signal wakeWordRequested(bool enabled)
    signal themeModeRequested(string mode)
    signal settingsActivated()

    onRoomsChanged: ensureSelectedRoom()

    Component.onCompleted: {
        updateClock()
        ensureSelectedRoom()
    }

    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape || event.key === Qt.Key_Back) {
            if (selectedColorDevice) {
                selectedColorDevice = null
            } else if (currentScreen === "room") {
                navigate("rooms")
            } else if (currentScreen !== "dashboard") {
                navigate("dashboard")
            }
            event.accepted = true
        }
    }

    Timer {
        running: true
        repeat: true
        interval: 1000
        onTriggered: root.updateClock()
    }

    Rectangle {
        anchors.fill: parent
        color: "#030504"
    }

    Item {
        id: surface
        width: 800
        height: 480
        x: (root.width - width * root.surfaceScale) / 2
        y: (root.height - height * root.surfaceScale) / 2
        scale: root.surfaceScale
        transformOrigin: Item.TopLeft
        clip: true

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0; color: root.currentScreen === "jarvis" ? "#0c1512" : root.backgroundTop }
                GradientStop { position: 0.56; color: root.backgroundBase }
                GradientStop { position: 1; color: root.backgroundBottom }
            }
        }

        DashboardScreen {
            opacity: root.currentScreen === "dashboard" ? 1 : 0
            visible: opacity > 0
            x: root.currentScreen === "dashboard" ? 0 : -8
        }

        RoomsScreen {
            opacity: root.currentScreen === "rooms" ? 1 : 0
            visible: opacity > 0
            x: root.currentScreen === "rooms" ? 0 : 8
        }

        RoomDetailScreen {
            opacity: root.currentScreen === "room" ? 1 : 0
            visible: opacity > 0
            x: root.currentScreen === "room" ? 0 : 8
        }

        HealthScreen {
            opacity: root.currentScreen === "health" ? 1 : 0
            visible: opacity > 0
            x: root.currentScreen === "health" ? 0 : 8
        }

        JarvisScreen {
            opacity: root.currentScreen === "jarvis" ? 1 : 0
            visible: opacity > 0
            x: root.currentScreen === "jarvis" ? 0 : 8
        }

        SettingsScreen {
            opacity: root.currentScreen === "settings" ? 1 : 0
            visible: opacity > 0
            x: root.currentScreen === "settings" ? 0 : 8
        }

        NavigationBar {
            z: 50
            opacity: root.selectedColorDevice ? 0.25 : 1
            enabled: !root.selectedColorDevice
        }

        ColorPicker {
            z: 70
            visible: root.selectedColorDevice !== null
        }
    }

    component ScreenBase: Item {
        width: 800
        height: 480

        Behavior on opacity {
            NumberAnimation { duration: root.transitionDuration; easing.type: Easing.OutCubic }
        }
        Behavior on x {
            NumberAnimation { duration: root.transitionDuration; easing.type: Easing.OutCubic }
        }
    }

    component Hairline: Rectangle {
        height: 1
        color: "transparent"
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "#00d9cba8" }
            GradientStop { position: 0.5; color: "#38d9cba8" }
            GradientStop { position: 1; color: "#00d9cba8" }
        }
    }

    component Panel: Rectangle {
        property bool active: false
        property color activeColor: root.accentGreen
        radius: 8
        color: active ? Qt.rgba(activeColor.r, activeColor.g, activeColor.b, 0.065) : "#05ffffff"
        border.width: 1
        border.color: active ? Qt.rgba(activeColor.r, activeColor.g, activeColor.b, 0.34) : "#24d9cba8"
        antialiasing: true

        Behavior on color {
            ColorAnimation { duration: root.transitionDuration; easing.type: Easing.OutCubic }
        }
        Behavior on border.color {
            ColorAnimation { duration: root.transitionDuration; easing.type: Easing.OutCubic }
        }
    }

    component ToggleSwitch: Item {
        id: toggle
        property bool checked: false
        property bool interactive: true
        signal toggled()
        width: 46
        height: 26

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: toggle.checked ? root.accentGreen : "#0fffffff"
            border.width: toggle.checked ? 0 : 1
            border.color: "#2ed9cba8"

            Behavior on color {
                ColorAnimation { duration: root.transitionDuration; easing.type: Easing.OutCubic }
            }
        }

        Rectangle {
            y: 3
            x: toggle.checked ? 23 : 3
            width: 20
            height: 20
            radius: 10
            color: toggle.checked ? "#07100c" : root.textMuted

            Behavior on x {
                NumberAnimation { duration: root.transitionDuration; easing.type: Easing.OutCubic }
            }
            Behavior on color {
                ColorAnimation { duration: root.transitionDuration; easing.type: Easing.OutCubic }
            }
        }

        MouseArea {
            anchors.fill: parent
            enabled: toggle.interactive
            onClicked: toggle.toggled()
        }
    }

    component Gauge: Item {
        id: gauge
        property real progress: 0.5
        property string valueText: "0"
        property string unitText: ""
        property string labelText: ""
        property string detailText: ""
        property color accent: root.accentGreen

        Canvas {
            id: gaugeCanvas
            anchors.fill: parent
            antialiasing: true

            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                var cx = width / 2
                var cy = height / 2
                var outer = Math.min(width, height) / 2 - 7
                var radius = outer - 12
                var start = Math.PI * 0.72
                var span = Math.PI * 1.56
                ctx.lineCap = "round"
                ctx.lineWidth = 1
                ctx.strokeStyle = "rgba(217,203,168,0.14)"
                ctx.beginPath()
                ctx.arc(cx, cy, outer, 0, Math.PI * 2)
                ctx.stroke()
                ctx.lineWidth = 10
                ctx.strokeStyle = gauge.accent === root.accentGold
                    ? "rgba(217,203,168,0.12)"
                    : "rgba(46,199,154,0.12)"
                ctx.beginPath()
                ctx.arc(cx, cy, radius, start, start + span)
                ctx.stroke()
                ctx.strokeStyle = gauge.accent
                ctx.beginPath()
                ctx.arc(cx, cy, radius, start, start + Math.max(0.02, Math.min(1, gauge.progress)) * span)
                ctx.stroke()
            }

            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            Connections {
                target: gauge
                function onProgressChanged() { gaugeCanvas.requestPaint() }
                function onAccentChanged() { gaugeCanvas.requestPaint() }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height / 2 - 32
            text: gauge.valueText
            color: root.textPrimary
            font.family: root.displayFont
            font.pixelSize: 40
            font.weight: Font.ExtraLight
        }

        Text {
            x: parent.width / 2 + 38
            y: parent.height / 2 - 16
            text: gauge.unitText
            color: root.textDim
            font.family: root.displayFont
            font.pixelSize: 15
            visible: text.length > 0
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height / 2 + 22
            width: parent.width - 24
            text: gauge.labelText
            color: root.textMuted
            font.family: root.monoFont
            font.pixelSize: 8
            font.letterSpacing: 3
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height / 2 + 38
            width: parent.width - 20
            text: gauge.detailText
            color: gauge.accent
            font.family: root.monoFont
            font.pixelSize: 8
            font.letterSpacing: 1
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
    }

    component HeaderTitle: Text {
        color: root.textPrimary
        font.family: root.displayFont
        font.pixelSize: 24
        font.weight: Font.Light
        font.letterSpacing: 2
        elide: Text.ElideRight
    }

    component DashboardScreen: ScreenBase {
        Item {
            x: 24
            y: 14
            width: 752
            height: 36

            Text {
                x: 0
                y: 4
                text: "VOKRR"
                color: root.accentGold
                font.family: root.displayFont
                font.pixelSize: 14
                font.weight: Font.Light
                font.letterSpacing: 6
            }

            Rectangle {
                x: 98
                y: 7
                width: 1
                height: 13
                color: "#40d9cba8"
            }

            Text {
                x: 115
                y: 6
                text: root.dateText
                color: root.textDim
                font.family: root.monoFont
                font.pixelSize: 10
                font.letterSpacing: 2
            }

            Text {
                x: 542
                y: -2
                width: 128
                text: root.clockText
                color: root.textPrimary
                font.family: root.displayFont
                font.pixelSize: 28
                font.weight: Font.ExtraLight
                font.letterSpacing: 3
                horizontalAlignment: Text.AlignRight
            }

            Text {
                x: 684
                y: 7
                width: 68
                text: root.weatherLabel()
                color: root.textDim
                font.family: root.monoFont
                font.pixelSize: 9
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
            }
        }

        Hairline { x: 24; y: 54; width: 752 }

        Gauge {
            x: 74
            y: 112
            width: 172
            height: 172
            progress: Math.max(0.06, root.activeDeviceCount(root.allDevices()) / Math.max(1, root.allDevices().length))
            valueText: String(root.homeLoadWatts())
            unitText: "W"
            labelText: "HOME LOAD"
            detailText: root.activeDeviceCount(root.allDevices()) + " OF " + root.allDevices().length + " ACTIVE"
        }

        Item {
            x: 275
            y: 98
            width: 250
            height: 210

            Item {
                id: dashboardCore
                anchors.horizontalCenter: parent.horizontalCenter
                y: 4
                width: 72
                height: 72

                Rectangle {
                    anchors.centerIn: parent
                    width: 66
                    height: 66
                    radius: 33
                    color: "transparent"
                    border.width: 1
                    border.color: "#732ec79a"
                    SequentialAnimation on scale {
                        running: !root.reducedMotion
                        loops: Animation.Infinite
                        NumberAnimation { from: 0.85; to: 1.12; duration: 1500; easing.type: Easing.OutCubic }
                        NumberAnimation { from: 1.12; to: 0.85; duration: 1500; easing.type: Easing.InOutCubic }
                    }
                    SequentialAnimation on opacity {
                        running: !root.reducedMotion
                        loops: Animation.Infinite
                        NumberAnimation { from: 0.7; to: 0.15; duration: 1500; easing.type: Easing.OutCubic }
                        NumberAnimation { from: 0.15; to: 0.7; duration: 1500; easing.type: Easing.InOutCubic }
                    }
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: 54
                    height: 54
                    radius: 27
                    color: "transparent"
                    border.width: 1
                    border.color: "#33d9cba8"
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: 40
                    height: 40
                    radius: 20
                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop { position: 0; color: "#7fe9c6" }
                        GradientStop { position: 0.48; color: root.accentGreen }
                        GradientStop { position: 1; color: "#0d5b45" }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.navigate("jarvis")
                }
            }

            Text {
                y: 92
                width: parent.width
                text: root.greetingText()
                color: root.textPrimary
                font.family: root.displayFont
                font.pixelSize: 18
                font.weight: Font.Light
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }

            Text {
                y: 121
                width: parent.width
                text: root.summaryText()
                color: root.textMuted
                font.family: root.displayFont
                font.pixelSize: 12
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 154
                width: 136
                height: 28
                radius: 14
                color: "transparent"
                border.width: 1
                border.color: "#47d9cba8"

                Text {
                    anchors.centerIn: parent
                    text: "SAY \"JARVIS\""
                    color: root.accentGold
                    font.family: root.monoFont
                    font.pixelSize: 9
                    font.letterSpacing: 2
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.navigate("jarvis")
                }
            }
        }

        Gauge {
            x: 554
            y: 112
            width: 172
            height: 172
            progress: isNaN(root.recoveryScore()) ? 0 : Math.max(0, root.recoveryScore()) / 100
            valueText: root.recoveryScoreText()
            labelText: "RECOVERY"
            detailText: "HR " + root.heartRateText() + " · SLEEP " + root.sleepDuration()
            accent: root.accentGold
        }

        Item {
            x: 24
            y: 356
            width: 752
            height: 38

            Row {
                anchors.fill: parent
                spacing: 8
                visible: root.rooms.length > 0

                Repeater {
                    model: Math.min(6, root.rooms.length)

                    Rectangle {
                        required property int index
                        property var room: root.rooms[index]
                        width: (752 - 8 * (Math.min(6, root.rooms.length) - 1)) / Math.max(1, Math.min(6, root.rooms.length))
                        height: 34
                        radius: 17
                        color: root.activeDeviceCount(room.devices) > 0 ? "#142ec79a" : "#04ffffff"
                        border.width: 1
                        border.color: root.activeDeviceCount(room.devices) > 0 ? "#592ec79a" : "#29d9cba8"

                        Row {
                            anchors.centerIn: parent
                            spacing: 7

                            Rectangle {
                                width: 6
                                height: 6
                                radius: 3
                                color: root.activeDeviceCount(room.devices) > 0 ? root.accentGreen : root.inactive
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                width: Math.max(38, parent.parent.width - 28)
                                text: root.compactRoomName(room.name)
                                color: root.textSecondary
                                font.family: root.displayFont
                                font.pixelSize: 10
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.openRoom(room)
                        }
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: root.rooms.length === 0
                text: root.authenticated ? "WAITING FOR HOME ASSISTANT" : "CONNECTING TO VOKRR"
                color: root.textDim
                font.family: root.monoFont
                font.pixelSize: 9
                font.letterSpacing: 2
            }
        }
    }

    component RoomsScreen: ScreenBase {
        HeaderTitle { x: 24; y: 13; width: 120; text: "Rooms" }

        Text {
            x: 150
            y: 28
            width: 470
            text: root.roomsSummary()
            color: root.textDim
            font.family: root.monoFont
            font.pixelSize: 9
            font.letterSpacing: 2
            elide: Text.ElideRight
        }

        Text {
            x: 650
            y: 17
            width: 126
            text: root.clockText
            color: root.textPrimary
            font.family: root.displayFont
            font.pixelSize: 22
            font.weight: Font.ExtraLight
            font.letterSpacing: 2
            horizontalAlignment: Text.AlignRight
        }

        Hairline { x: 24; y: 59; width: 752 }

        Flickable {
            x: 24
            y: 72
            width: 752
            height: 326
            clip: true
            contentWidth: width
            contentHeight: Math.max(height, Math.ceil(root.rooms.length / 3) * 157)
            boundsBehavior: Flickable.StopAtBounds

            Grid {
                width: parent.width
                columns: 3
                columnSpacing: 12
                rowSpacing: 12

                Repeater {
                    model: root.rooms.length

                    Panel {
                        required property int index
                        property var room: root.rooms[index]
                        width: (752 - 24) / 3
                        height: 145
                        active: root.activeDeviceCount(room.devices) > 0

                        Text {
                            x: 16
                            y: 13
                            width: parent.width - 48
                            text: room.name
                            color: root.textPrimary
                            font.family: root.displayFont
                            font.pixelSize: 17
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            x: parent.width - 25
                            y: 21
                            width: 7
                            height: 7
                            radius: 4
                            color: root.activeDeviceCount(room.devices) > 0 ? root.accentGreen : root.inactive
                        }

                        Text {
                            x: 16
                            y: 93
                            width: parent.width - 32
                            text: room.devices.length + " DEVICE" + (room.devices.length === 1 ? "" : "S") + " · " + root.activeDeviceCount(room.devices) + " ON"
                            color: root.textMuted
                            font.family: root.monoFont
                            font.pixelSize: 9
                            font.letterSpacing: 1
                            elide: Text.ElideRight
                        }

                        Text {
                            x: 16
                            y: 113
                            width: parent.width - 32
                            text: root.roomLoadWatts(room) + "W LOAD"
                            color: root.textDim
                            font.family: root.monoFont
                            font.pixelSize: 9
                            font.letterSpacing: 1
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.openRoom(room)
                        }
                    }
                }
            }

            ScrollIndicator.vertical: ScrollIndicator { }
        }

        Text {
            anchors.centerIn: parent
            visible: root.rooms.length === 0
            text: root.backendOnline ? "NO ROOMS CONFIGURED" : "HOME ASSISTANT OFFLINE"
            color: root.textDim
            font.family: root.monoFont
            font.pixelSize: 10
            font.letterSpacing: 2
        }
    }

    component RoomDetailScreen: ScreenBase {
        property var room: root.selectedRoom()
        property var devices: room && room.devices ? room.devices : []

        Rectangle {
            x: 24
            y: 14
            width: 40
            height: 40
            radius: 20
            color: "transparent"
            border.width: 1
            border.color: "#4dd9cba8"

            Text {
                anchors.centerIn: parent
                text: "‹"
                color: root.accentGold
                font.family: root.displayFont
                font.pixelSize: 26
                font.weight: Font.Light
                y: -2
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.navigate("rooms")
            }
        }

        Text {
            x: 78
            y: 12
            width: 420
            text: room ? room.name : "Room"
            color: root.textPrimary
            font.family: root.displayFont
            font.pixelSize: 22
            font.weight: Font.Light
            font.letterSpacing: 1.5
            elide: Text.ElideRight
        }

        Text {
            x: 78
            y: 40
            width: 420
            text: room ? root.activeDeviceCount(devices) + " OF " + devices.length + " ACTIVE · " + root.roomLoadWatts(room) + "W" : "NO ROOM SELECTED"
            color: root.textDim
            font.family: root.monoFont
            font.pixelSize: 9
            font.letterSpacing: 2
            elide: Text.ElideRight
        }

        Rectangle {
            x: 664
            y: 18
            width: 112
            height: 32
            radius: 16
            color: "transparent"
            border.width: 1
            border.color: "#47d9cba8"
            opacity: room && root.activeDeviceCount(devices) > 0 ? 1 : 0.45

            Text {
                anchors.centerIn: parent
                text: "ALL OFF"
                color: root.accentGold
                font.family: root.displayFont
                font.pixelSize: 11
                font.letterSpacing: 2
            }

            MouseArea {
                anchors.fill: parent
                enabled: room && root.activeDeviceCount(devices) > 0
                onClicked: root.roomSetRequested(room, false)
            }
        }

        Hairline { x: 24; y: 65; width: 752 }

        Flickable {
            x: 24
            y: 78
            width: 752
            height: 320
            clip: true
            contentWidth: width
            contentHeight: Math.max(height, Math.ceil(devices.length / 3) * 153)
            boundsBehavior: Flickable.StopAtBounds

            Grid {
                width: parent.width
                columns: 3
                columnSpacing: 12
                rowSpacing: 12

                Repeater {
                    model: root.selectedRoomDevices().length

                    Panel {
                        id: deviceCard
                        required property int index
                        property var device: root.selectedRoomDevice(index)
                        property color actualColor: root.deviceColor(device)
                        width: (752 - 24) / 3
                        height: 141
                        active: root.deviceIsOn(device)
                        activeColor: root.deviceHasColor(device) ? actualColor : root.accentGreen

                        Text {
                            x: 14
                            y: 11
                            width: parent.width - (root.deviceHasColor(deviceCard.device) ? 60 : 28)
                            text: deviceCard.device ? deviceCard.device.name : "Device"
                            color: root.textPrimary
                            font.family: root.displayFont
                            font.pixelSize: 15
                            elide: Text.ElideRight
                        }

                        Text {
                            x: 14
                            y: 36
                            width: parent.width - 28
                            text: root.deviceTypeLabel(deviceCard.device)
                            color: root.textDim
                            font.family: root.monoFont
                            font.pixelSize: 8
                            font.letterSpacing: 1.5
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            x: parent.width - 43
                            y: 11
                            width: 27
                            height: 27
                            radius: 14
                            visible: root.deviceHasColor(deviceCard.device)
                            color: deviceCard.actualColor
                            border.width: 2
                            border.color: root.deviceIsOn(deviceCard.device) ? root.textPrimary : root.textDim

                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.openColorPicker(deviceCard.device)
                            }
                        }

                        Text {
                            x: 14
                            y: 104
                            width: parent.width - 90
                            text: root.deviceStatus(deviceCard.device)
                            color: root.deviceIsOn(deviceCard.device) ? (root.deviceHasColor(deviceCard.device) ? deviceCard.actualColor : root.accentGreen) : root.textDim
                            font.family: root.monoFont
                            font.pixelSize: 9
                            font.letterSpacing: 1
                            elide: Text.ElideRight
                        }

                        ToggleSwitch {
                            x: parent.width - 60
                            y: 94
                            checked: root.deviceIsOn(deviceCard.device)
                            interactive: root.hasCapability(deviceCard.device, "toggle")
                            onToggled: root.deviceToggleRequested(deviceCard.device)
                        }
                    }
                }
            }

            ScrollIndicator.vertical: ScrollIndicator { }
        }

        Text {
            anchors.centerIn: parent
            visible: room && devices.length === 0
            text: "NO CONTROLLABLE DEVICES"
            color: root.textDim
            font.family: root.monoFont
            font.pixelSize: 10
            font.letterSpacing: 2
        }
    }

    component HealthScreen: ScreenBase {
        HeaderTitle { x: 24; y: 13; width: 120; text: "Health" }

        Text {
            x: 150
            y: 28
            width: 340
            text: root.healthSyncLabel()
            color: root.healthConnected() ? root.textDim : "#d98f72"
            font.family: root.monoFont
            font.pixelSize: 8
            font.letterSpacing: 1.4
            elide: Text.ElideRight
        }

        Row {
            x: 540
            y: 16
            spacing: 6

            Repeater {
                model: [{ label: "TODAY", days: 1 }, { label: "WEEK", days: 7 }]

                Rectangle {
                    id: healthRangeButton
                    required property var modelData
                    property bool active: root.healthRangeDays === healthRangeButton.modelData.days
                    width: 70
                    height: 28
                    radius: 14
                    activeFocusOnTab: true
                    Accessible.role: Accessible.Button
                    Accessible.name: healthRangeButton.modelData.label + " health range"
                    color: active ? "#16d9cba8" : "transparent"
                    border.width: 1
                    border.color: activeFocus ? root.accentGreen : active ? "#66d9cba8" : "#29d9cba8"

                    Keys.onPressed: function(event) {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                            root.healthRangeRequested(healthRangeButton.modelData.days)
                            event.accepted = true
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: healthRangeButton.modelData.label
                        color: parent.active ? root.accentGold : root.textMuted
                        font.family: root.displayFont
                        font.pixelSize: 10
                        font.letterSpacing: 1.5
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: !root.healthLoading
                        onClicked: root.healthRangeRequested(healthRangeButton.modelData.days)
                    }
                }
            }

            Rectangle {
                id: healthRefreshButton
                width: 36
                height: 28
                radius: 14
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: "Refresh Ultrahuman health data"
                color: refreshArea.pressed ? "#16d9cba8" : "transparent"
                border.width: 1
                border.color: activeFocus ? root.accentGreen : "#29d9cba8"

                Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                        root.healthRefreshRequested()
                        event.accepted = true
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: root.healthLoading ? "..." : "↻"
                    color: root.healthLoading ? root.textDim : root.accentGreen
                    font.family: root.displayFont
                    font.pixelSize: root.healthLoading ? 12 : 18
                }

                MouseArea {
                    id: refreshArea
                    anchors.fill: parent
                    enabled: !root.healthLoading
                    onClicked: root.healthRefreshRequested()
                }
            }
        }

        Hairline { x: 24; y: 59; width: 752 }

        Panel {
            x: 24
            y: 72
            width: 210
            height: 326

            Gauge {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 18
                width: 126
                height: 126
                progress: isNaN(root.recoveryScore()) ? 0 : Math.max(0, root.recoveryScore()) / 100
                valueText: root.recoveryScoreText()
                labelText: "RECOVERY"
                accent: root.accentGold
            }

            Text {
                y: 151
                width: parent.width
                text: root.healthCurrent() ? "LATEST VALIDATED METRICS" : "NO VALIDATED RING DATA"
                color: root.healthCurrent() ? root.accentGold : root.textDim
                font.family: root.monoFont
                font.pixelSize: 8
                font.letterSpacing: 1
                horizontalAlignment: Text.AlignHCenter
            }

            Grid {
                x: 12
                y: 190
                columns: 2
                rowSpacing: 15
                columnSpacing: 6

                Repeater {
                    model: root.healthMetricCards()

                    Column {
                        id: healthMetricCard
                        required property var modelData
                        width: 90
                        spacing: 2

                        Text {
                            width: parent.width
                            text: healthMetricCard.modelData.value
                            color: healthMetricCard.modelData.available ? root.textPrimary : root.textDim
                            font.family: root.displayFont
                            font.pixelSize: 16
                            font.weight: Font.Light
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: healthMetricCard.modelData.label
                            color: root.textDim
                            font.family: root.monoFont
                            font.pixelSize: 7
                            font.letterSpacing: 0.6
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }

        Panel {
            x: 246
            y: 72
            width: 530
            height: 178

            Text {
                x: 16
                y: 12
                text: root.healthRangeDays === 7 ? "HEART RATE · 7 DAYS" : "HEART RATE · TODAY"
                color: root.textDim
                font.family: root.monoFont
                font.pixelSize: 9
                font.letterSpacing: 2
            }

            Text {
                x: 354
                y: 7
                width: 158
                text: root.heartRateText() + (root.heartRate() >= 0 ? " BPM" : "")
                color: root.heartRate() >= 0 ? root.accentGreen : root.textDim
                font.family: root.displayFont
                font.pixelSize: 20
                font.weight: Font.Light
                horizontalAlignment: Text.AlignRight
            }

            Canvas {
                id: heartChart
                property var points: root.heartChartPoints()
                property int selectedIndex: -1
                x: 16
                y: 42
                width: parent.width - 32
                height: 94
                antialiasing: true
                Accessible.name: root.heartChartSummary()

                onPointsChanged: {
                    selectedIndex = -1
                    requestPaint()
                }
                onSelectedIndexChanged: requestPaint()
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    ctx.strokeStyle = "rgba(138,150,145,0.12)"
                    ctx.lineWidth = 1
                    for (var grid = 1; grid < 4; grid++) {
                        var gy = grid * height / 4
                        ctx.beginPath(); ctx.moveTo(0, gy); ctx.lineTo(width, gy); ctx.stroke()
                    }
                    if (!points || points.length < 2)
                        return
                    var low = Number(points[0].value)
                    var high = low
                    for (var i = 1; i < points.length; i++) {
                        low = Math.min(low, Number(points[i].value))
                        high = Math.max(high, Number(points[i].value))
                    }
                    var span = Math.max(8, high - low)
                    low -= span * 0.12
                    high += span * 0.12
                    var step = width / (points.length - 1)
                    ctx.beginPath()
                    for (var point = 0; point < points.length; point++) {
                        var px = point * step
                        var py = height - (Number(points[point].value) - low) / (high - low) * height
                        if (point === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py)
                    }
                    ctx.strokeStyle = root.accentGreen
                    ctx.lineWidth = 1.6
                    ctx.stroke()
                    if (selectedIndex >= 0 && selectedIndex < points.length) {
                        var sx = selectedIndex * step
                        var sy = height - (Number(points[selectedIndex].value) - low) / (high - low) * height
                        ctx.fillStyle = root.accentGold
                        ctx.beginPath(); ctx.arc(sx, sy, 3.5, 0, Math.PI * 2); ctx.fill()
                    }
                }
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onPositionChanged: function(mouse) {
                        if (!heartChart.points || heartChart.points.length < 2)
                            return
                        heartChart.selectedIndex = Math.max(0, Math.min(
                            heartChart.points.length - 1,
                            Math.round(mouse.x / width * (heartChart.points.length - 1))))
                    }
                    onExited: heartChart.selectedIndex = -1
                }
            }

            Text {
                x: 16
                y: 139
                width: 498
                text: heartChart.selectedIndex >= 0
                    ? root.chartPointLabel(heartChart.points[heartChart.selectedIndex])
                    : root.chartAxisLabel(heartChart.points)
                color: heartChart.selectedIndex >= 0 ? root.accentGold : root.inactive
                font.family: root.monoFont
                font.pixelSize: 8
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }

            Text {
                anchors.centerIn: heartChart
                visible: !heartChart.points || heartChart.points.length < 2
                text: root.healthLoading ? "SYNCING RING DATA" : "HEART RATE UNAVAILABLE"
                color: root.textDim
                font.family: root.monoFont
                font.pixelSize: 9
                font.letterSpacing: 1.3
            }
        }

        Panel {
            x: 246
            y: 262
            width: 530
            height: 136

            Text {
                x: 16
                y: 12
                text: "SLEEP · LAST NIGHT"
                color: root.textDim
                font.family: root.monoFont
                font.pixelSize: 9
                font.letterSpacing: 2
            }

            Text {
                x: 320
                y: 8
                width: 192
                text: root.sleepHeadline()
                color: root.hasSleepData() ? root.textPrimary : root.textDim
                font.family: root.displayFont
                font.pixelSize: 17
                font.weight: Font.Light
                horizontalAlignment: Text.AlignRight
            }

            Row {
                x: 16
                y: 49
                width: 498
                height: 13
                visible: root.sleepStageModel().length > 0

                Repeater {
                    model: root.sleepStageModel()

                    Rectangle {
                        id: sleepStageBar
                        required property var modelData
                        width: 498 * sleepStageBar.modelData.percentage / 100
                        height: 13
                        color: sleepStageBar.modelData.color
                    }
                }
            }

            Row {
                x: 16
                y: 77
                width: 498
                visible: root.sleepStageModel().length > 0

                Repeater {
                    model: root.sleepStageModel()

                    Row {
                        id: sleepStageLegend
                        required property var modelData
                        width: 124
                        spacing: 5
                        Rectangle {
                            width: 6
                            height: 6
                            radius: 3
                            color: sleepStageLegend.modelData.color
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            width: 110
                            text: sleepStageLegend.modelData.label
                            color: root.textDim
                            font.family: root.monoFont
                            font.pixelSize: 7
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            Text {
                x: 16
                y: 106
                width: 498
                text: "WELLNESS DATA · NOT A MEDICAL DIAGNOSIS · FRESHNESS DEPENDS ON RING AND APP SYNC"
                color: root.inactive
                font.family: root.monoFont
                font.pixelSize: 7
                font.letterSpacing: 0.45
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }

            Text {
                anchors.centerIn: parent
                visible: root.sleepStageModel().length === 0
                text: "SLEEP STAGES UNAVAILABLE"
                color: root.textDim
                font.family: root.monoFont
                font.pixelSize: 9
                font.letterSpacing: 1.3
            }
        }
    }

    component JarvisScreen: ScreenBase {
        Text {
            x: 30
            y: 20
            width: 320
            text: root.jarvisStateLabel()
            color: root.wakeWordEnabled ? root.accentGreen : root.textDim
            font.family: root.monoFont
            font.pixelSize: 9
            font.letterSpacing: 3
            elide: Text.ElideRight
        }

        Text {
            x: 650
            y: 20
            width: 120
            text: root.clockText
            color: root.accentGold
            font.family: root.monoFont
            font.pixelSize: 9
            font.letterSpacing: 3
            horizontalAlignment: Text.AlignRight
        }

        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 62
            width: 148
            height: 148

            Repeater {
                model: 2
                Rectangle {
                    required property int index
                    anchors.centerIn: parent
                    width: 132
                    height: 132
                    radius: 66
                    color: "transparent"
                    border.width: 1
                    border.color: index === 0 ? "#662ec79a" : "#4dd9cba8"
                    opacity: 0
                    scale: 0.8

                    SequentialAnimation on scale {
                        running: root.wakeWordEnabled && !root.reducedMotion
                        loops: Animation.Infinite
                        PauseAnimation { duration: index * 1300 }
                        NumberAnimation { from: 0.8; to: 1.48; duration: 2600; easing.type: Easing.OutCubic }
                    }
                    SequentialAnimation on opacity {
                        running: root.wakeWordEnabled && !root.reducedMotion
                        loops: Animation.Infinite
                        PauseAnimation { duration: index * 1300 }
                        NumberAnimation { from: 0.65; to: 0; duration: 2600; easing.type: Easing.OutCubic }
                    }
                }
            }

            Rectangle {
                anchors.centerIn: parent
                width: 92
                height: 92
                radius: 46
                color: "transparent"
                border.width: 1
                border.color: "#33d9cba8"
                RotationAnimation on rotation {
                    running: root.wakeWordEnabled && !root.reducedMotion
                    from: 0
                    to: 360
                    duration: 30000
                    loops: Animation.Infinite
                }
            }

            Rectangle {
                anchors.centerIn: parent
                width: 70
                height: 70
                radius: 35
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0; color: root.wakeWordEnabled ? "#9defd0" : "#5f6b66" }
                    GradientStop { position: 0.48; color: root.wakeWordEnabled ? root.accentGreen : root.inactive }
                    GradientStop { position: 1; color: root.wakeWordEnabled ? "#0d5b45" : "#111514" }
                }
                SequentialAnimation on scale {
                    running: root.voicePipelineActive && !root.reducedMotion
                    loops: Animation.Infinite
                    NumberAnimation { from: 0.96; to: 1.04; duration: 1400; easing.type: Easing.InOutCubic }
                    NumberAnimation { from: 1.04; to: 0.96; duration: 1400; easing.type: Easing.InOutCubic }
                }
            }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 229
            height: 22
            spacing: 4

            Repeater {
                model: [0.4, 0.75, 1.0, 0.65, 0.45]

                Rectangle {
                    required property real modelData
                    required property int index
                    width: 3
                    height: 22 * modelData
                    radius: 2
                    color: index === 0 || index === 4 ? root.accentGold : root.accentGreen
                    anchors.verticalCenter: parent.verticalCenter
                    opacity: root.voicePipelineActive ? 1 : 0.45

                    SequentialAnimation on scale {
                        running: root.voicePipelineActive && !root.reducedMotion
                        loops: Animation.Infinite
                        PauseAnimation { duration: index * 90 }
                        NumberAnimation { from: 0.55; to: 1.15; duration: 440; easing.type: Easing.InOutCubic }
                        NumberAnimation { from: 1.15; to: 0.55; duration: 440; easing.type: Easing.InOutCubic }
                    }
                }
            }
        }

        Text {
            x: 120
            y: 267
            width: 560
            text: root.jarvisPrompt()
            color: root.textDim
            font.family: root.monoFont
            font.pixelSize: 10
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }

        Text {
            x: 120
            y: 298
            width: 560
            height: 64
            text: root.jarvisReply()
            color: root.textPrimary
            font.family: root.displayFont
            font.pixelSize: 21
            font.weight: Font.Light
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignTop
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 370
            spacing: 10

            Rectangle {
                width: 182
                height: 30
                radius: 15
                color: "transparent"
                border.width: 1
                border.color: "#592ec79a"
                Text {
                    anchors.centerIn: parent
                    text: root.voicePipelineActive ? "VOICE ONLINE" : "BEDROOM SOCKETS · READY"
                    color: root.accentGreen
                    font.family: root.monoFont
                    font.pixelSize: 9
                    font.letterSpacing: 1.2
                }
            }

            Rectangle {
                width: 150
                height: 30
                radius: 15
                color: "transparent"
                border.width: 1
                border.color: "#33d9cba8"
                Text {
                    anchors.centerIn: parent
                    text: "TAP TO DISMISS"
                    color: root.textMuted
                    font.family: root.monoFont
                    font.pixelSize: 9
                    font.letterSpacing: 1.2
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: root.navigate("dashboard")
                }
            }
        }
    }

    component SettingsScreen: ScreenBase {
        HeaderTitle { x: 24; y: 13; width: 150; text: "Settings" }

        Text {
            x: 390
            y: 26
            width: 386
            text: root.systemLabel()
            color: root.inactive
            font.family: root.monoFont
            font.pixelSize: 9
            font.letterSpacing: 2
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideLeft
        }

        Hairline { x: 24; y: 59; width: 752 }

        Column {
            x: 24
            y: 72
            width: 752
            spacing: 8

            Panel {
                width: parent.width
                height: 58

                Text {
                    x: 18
                    y: 8
                    text: "Wake word"
                    color: root.textPrimary
                    font.family: root.displayFont
                    font.pixelSize: 15
                }
                Text {
                    x: 18
                    y: 33
                    text: "LISTENING FOR \"JARVIS\""
                    color: root.textDim
                    font.family: root.monoFont
                    font.pixelSize: 9
                    font.letterSpacing: 1
                }
                Text {
                    x: 596
                    y: 23
                    width: 72
                    text: root.wakeWordEnabled ? "ACTIVE" : "MUTED"
                    color: root.wakeWordEnabled ? root.accentGreen : root.textDim
                    font.family: root.monoFont
                    font.pixelSize: 9
                    font.letterSpacing: 1
                    horizontalAlignment: Text.AlignRight
                }
                ToggleSwitch {
                    x: 686
                    y: 16
                    checked: root.wakeWordEnabled
                    onToggled: root.wakeWordRequested(!root.wakeWordEnabled)
                }
            }

            Panel {
                width: parent.width
                height: 58

                Text {
                    x: 18
                    y: 8
                    text: "Theme"
                    color: root.textPrimary
                    font.family: root.displayFont
                    font.pixelSize: 15
                }
                Text {
                    x: 18
                    y: 33
                    text: "AUTO SWITCHES AT SUNRISE / SUNSET"
                    color: root.textDim
                    font.family: root.monoFont
                    font.pixelSize: 9
                    font.letterSpacing: 1
                }

                Row {
                    x: 500
                    y: 15
                    spacing: 6

                    Repeater {
                        model: ["DARK", "LIGHT", "AUTO"]

                        Rectangle {
                            required property string modelData
                            property bool selected: root.themeMode === modelData
                            width: 70
                            height: 28
                            radius: 14
                            color: selected ? "#16d9cba8" : "transparent"
                            border.width: 1
                            border.color: selected ? "#73d9cba8" : "#29d9cba8"

                            Text {
                                anchors.centerIn: parent
                                text: modelData
                                color: parent.selected ? root.accentGold : root.textMuted
                                font.family: root.displayFont
                                font.pixelSize: 10
                                font.letterSpacing: 1.5
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.themeModeRequested(modelData)
                            }
                        }
                    }
                }
            }

            SettingsStatusRow {
                title: "Home Assistant"
                subtitle: root.homeAssistantSubtitle()
                statusText: root.backendOnline ? "● LINKED" : "● OFFLINE"
                statusColor: root.backendOnline ? root.accentGreen : "#d97c68"
            }

            SettingsStatusRow {
                title: "Ultrahuman Ring"
                subtitle: root.ultrahumanSubtitle()
                statusText: root.healthConnected() ? "● CONNECTED" : "● NOT CONNECTED"
                statusColor: root.healthConnected() ? root.accentGreen : "#d98f72"
            }

            SettingsStatusRow {
                title: "Display"
                subtitle: "AUTO BRIGHTNESS · NIGHT DIM 23:00"
                statusText: "7\" · 800×480"
                statusColor: root.textMuted
            }
        }
    }

    component SettingsStatusRow: Panel {
        id: statusRow
        property string title: ""
        property string subtitle: ""
        property string statusText: ""
        property color statusColor: root.textMuted
        width: 752
        height: 58

        Text {
            x: 18
            y: 8
            text: statusRow.title
            color: root.textPrimary
            font.family: root.displayFont
            font.pixelSize: 15
        }
        Text {
            x: 18
            y: 33
            width: 500
            text: statusRow.subtitle
            color: root.textDim
            font.family: root.monoFont
            font.pixelSize: 9
            font.letterSpacing: 1
            elide: Text.ElideRight
        }
        Text {
            x: 530
            y: 23
            width: 204
            text: statusRow.statusText
            color: statusRow.statusColor
            font.family: root.monoFont
            font.pixelSize: 9
            font.letterSpacing: 1
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideLeft
        }
    }

    component NavigationBar: Rectangle {
        id: nav
        x: 271
        y: 410
        width: 258
        height: 58
        radius: 29
        color: "#dc070a09"
        border.width: 1
        border.color: "#38d9cba8"

        Row {
            x: 6
            y: 6
            spacing: 4

            NavButton { screen: "dashboard"; iconName: "dashboard" }
            NavButton { screen: "rooms"; iconName: "rooms" }
            NavButton { screen: "health"; iconName: "health" }
            NavButton { screen: "jarvis"; iconName: "jarvis" }
            NavButton { screen: "settings"; iconName: "settings" }
        }

        Behavior on opacity {
            NumberAnimation { duration: root.transitionDuration; easing.type: Easing.OutCubic }
        }
    }

    component NavButton: Rectangle {
        id: navButton
        property string screen: "dashboard"
        property string iconName: "dashboard"
        property bool selected: root.currentScreen === screen || (screen === "rooms" && root.currentScreen === "room")
        width: 46
        height: 46
        radius: 23
        color: selected ? "#212ec79a" : "transparent"

        Image {
            id: navImage
            anchors.centerIn: parent
            width: 24
            height: 24
            property int revision: 0
            source: Qt.resolvedUrl("../assets/icons/gt/nav-" + navButton.iconName + (navButton.selected ? "-active" : "") + ".svg") + "#" + revision
            sourceSize: Qt.size(48, 48)
            fillMode: Image.PreserveAspectFit
            smooth: true
            asynchronous: false
            cache: false

            Connections {
                target: root
                function onCurrentScreenChanged() { navImage.revision++ }
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.navigate(navButton.screen)
        }

        Behavior on color {
            ColorAnimation { duration: root.transitionDuration; easing.type: Easing.OutCubic }
        }
    }

    component ColorPicker: Item {
        anchors.fill: parent

        Rectangle {
            anchors.fill: parent
            color: "#85000000"
            MouseArea {
                anchors.fill: parent
                onClicked: root.selectedColorDevice = null
            }
        }

        Panel {
            id: pickerPanel
            x: 170
            y: 226
            width: 460
            height: 172
            active: true

            Text {
                x: 18
                y: 13
                width: 290
                text: root.selectedColorDevice ? root.selectedColorDevice.name : "Light color"
                color: root.textPrimary
                font.family: root.displayFont
                font.pixelSize: 17
                elide: Text.ElideRight
            }

            Text {
                x: 18
                y: 39
                width: 290
                text: root.selectedColorDevice ? root.colorName(root.selectedColorDevice) : ""
                color: root.textDim
                font.family: root.monoFont
                font.pixelSize: 9
                font.letterSpacing: 1.5
                elide: Text.ElideRight
            }

            Rectangle {
                x: 410
                y: 10
                width: 38
                height: 38
                radius: 19
                color: "transparent"
                border.width: 1
                border.color: "#33d9cba8"

                Text {
                    anchors.centerIn: parent
                    text: "×"
                    color: root.textMuted
                    font.family: root.displayFont
                    font.pixelSize: 20
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.selectedColorDevice = null
                }
            }

            Row {
                x: 18
                y: 67
                spacing: 10

                Repeater {
                    model: root.colorOptions(root.selectedColorDevice)

                    Item {
                        required property var modelData
                        width: 43
                        height: 54

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 34
                            height: 34
                            radius: 17
                            color: modelData.color
                            border.width: root.colorOptionSelected(root.selectedColorDevice, modelData) ? 3 : 1
                            border.color: root.colorOptionSelected(root.selectedColorDevice, modelData) ? root.textPrimary : "#55ffffff"
                        }

                        Text {
                            y: 40
                            width: parent.width
                            text: modelData.label
                            color: root.textDim
                            font.family: root.monoFont
                            font.pixelSize: 7
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.applyColor(modelData)
                        }
                    }
                }
            }

            Text {
                x: 18
                y: 137
                text: "BRIGHTNESS"
                color: root.textDim
                font.family: root.monoFont
                font.pixelSize: 8
                font.letterSpacing: 1.5
            }

            Rectangle {
                x: 118
                y: 143
                width: 278
                height: 4
                radius: 2
                color: "#24d9cba8"

                Rectangle {
                    width: parent.width * root.paletteBrightness / 100
                    height: parent.height
                    radius: 2
                    color: root.deviceColor(root.selectedColorDevice)
                }

                Rectangle {
                    x: parent.width * root.paletteBrightness / 100 - 8
                    y: -6
                    width: 16
                    height: 16
                    radius: 8
                    color: root.textPrimary
                    border.width: 2
                    border.color: root.deviceColor(root.selectedColorDevice)
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.topMargin: -16
                    anchors.bottomMargin: -16
                    preventStealing: true
                    onPressed: function(mouse) {
                        root.paletteBrightness = root.brightnessFromPosition(mouse.x, parent.width)
                    }
                    onPositionChanged: function(mouse) {
                        if (pressed)
                            root.paletteBrightness = root.brightnessFromPosition(mouse.x, parent.width)
                    }
                    onReleased: root.commitBrightness()
                }
            }

            Text {
                x: 408
                y: 136
                width: 40
                text: Math.round(root.paletteBrightness) + "%"
                color: root.textSecondary
                font.family: root.monoFont
                font.pixelSize: 9
                horizontalAlignment: Text.AlignRight
            }
        }
    }

    function navigate(screen) {
        selectedColorDevice = null
        currentScreen = screen
        if (screen === "settings")
            settingsActivated()
    }

    function updateClock() {
        var now = new Date()
        var hours = String(now.getHours()).padStart(2, "0")
        var minutes = String(now.getMinutes()).padStart(2, "0")
        var days = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
        var months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
        clockText = hours + ":" + minutes
        dateText = days[now.getDay()] + " " + now.getDate() + " " + months[now.getMonth()]
    }

    function ensureSelectedRoom() {
        if (!rooms || rooms.length === 0) {
            selectedRoomId = ""
            if (currentScreen === "room")
                currentScreen = "rooms"
            return
        }
        for (var i = 0; i < rooms.length; i++) {
            if (rooms[i].id === selectedRoomId)
                return
        }
        selectedRoomId = rooms[0].id
    }

    function openRoom(room) {
        if (!room)
            return
        selectedRoomId = room.id
        navigate("room")
    }

    function selectedRoom() {
        for (var i = 0; i < rooms.length; i++) {
            if (rooms[i].id === selectedRoomId)
                return rooms[i]
        }
        return rooms.length ? rooms[0] : null
    }

    function selectedRoomDevices() {
        var room = selectedRoom()
        return room && room.devices ? room.devices : []
    }

    function selectedRoomDevice(index) {
        var devices = selectedRoomDevices()
        return index >= 0 && index < devices.length ? devices[index] : null
    }

    function allDevices() {
        var result = []
        for (var i = 0; i < rooms.length; i++) {
            var devices = rooms[i].devices || []
            for (var j = 0; j < devices.length; j++)
                result.push(devices[j])
        }
        return result
    }

    function activeDeviceCount(devices) {
        var count = 0
        var list = devices || []
        for (var i = 0; i < list.length; i++) {
            if (deviceIsOn(list[i]))
                count++
        }
        return count
    }

    function compactRoomName(name) {
        return String(name || "ROOM").replace(" Room", "").toUpperCase()
    }

    function roomsSummary() {
        var devices = allDevices()
        return rooms.length + " ROOMS · " + activeDeviceCount(devices) + " OF " + devices.length + " DEVICES ON · " + homeLoadWatts() + "W"
    }

    function hasCapability(device, capability) {
        return !!(device && device.capabilities && device.capabilities.indexOf(capability) !== -1)
    }

    function deviceIsOn(device) {
        return !!(device && device.state && device.state.is_on)
    }

    function deviceHasColor(device) {
        return hasCapability(device, "color") || hasCapability(device, "color_temperature")
    }

    function deviceTypeLabel(device) {
        if (!device)
            return "DEVICE"
        var raw = String((device.type || "") + " " + (device.name || "") + " " + (device.entity_id || "")).toLowerCase()
        if (raw.indexOf("tube") !== -1 || raw.indexOf("bulb") !== -1 || raw.indexOf("light") !== -1)
            return "LIGHT"
        if (raw.indexOf("fan") !== -1)
            return "FAN"
        if (raw.indexOf("geyser") !== -1 || raw.indexOf("heater") !== -1)
            return "WATER HEATER"
        if (raw.indexOf("socket") !== -1 || raw.indexOf("plug") !== -1)
            return "POWER"
        return String(device.type || "DEVICE").toUpperCase()
    }

    function deviceStatus(device) {
        if (!device || !device.state)
            return "UNKNOWN"
        if (!device.state.is_on)
            return "OFF"
        var level = null
        if (device.state.brightness !== undefined && device.state.brightness !== null)
            level = Math.round(Number(device.state.brightness))
        else if (device.state.percentage !== undefined && device.state.percentage !== null)
            level = Math.round(Number(device.state.percentage))
        return level === null ? "ON" : "ON · " + level + "%"
    }

    function estimateWatts(device) {
        if (!deviceIsOn(device))
            return 0
        var attrs = device.state && device.state.attributes ? device.state.attributes : {}
        var keys = ["power", "current_power_w", "power_w", "wattage"]
        for (var i = 0; i < keys.length; i++) {
            if (attrs[keys[i]] !== undefined && !isNaN(Number(attrs[keys[i]])))
                return Math.round(Number(attrs[keys[i]]))
        }
        var type = deviceTypeLabel(device)
        if (type === "LIGHT") return 18
        if (type === "FAN") return 45
        if (type === "WATER HEATER") return 2000
        if (type === "POWER") return 30
        return 12
    }

    function homeLoadWatts() {
        var devices = allDevices()
        var total = 0
        for (var i = 0; i < devices.length; i++)
            total += estimateWatts(devices[i])
        return total
    }

    function roomLoadWatts(room) {
        var devices = room && room.devices ? room.devices : []
        var total = 0
        for (var i = 0; i < devices.length; i++)
            total += estimateWatts(devices[i])
        return total
    }

    function healthCurrent() {
        return health && health.current ? health.current : null
    }

    function metricNumber(metric) {
        if (!metric || metric.value === undefined || metric.value === null)
            return NaN
        var value = Number(metric.value)
        return value
    }

    function numberText(value, decimals) {
        if (isNaN(value))
            return "--"
        var text = Number(value).toFixed(decimals)
        return decimals > 0 ? text.replace(/\.0+$/, "") : text
    }

    function recoveryScore() {
        var current = healthCurrent()
        return current && current.recovery ? metricNumber(current.recovery.score) : NaN
    }

    function recoveryScoreText() {
        return numberText(recoveryScore(), 0)
    }

    function heartRate() {
        var current = healthCurrent()
        return current ? metricNumber(current.latest_heart_rate) : NaN
    }

    function heartRateText() {
        return numberText(heartRate(), 0)
    }

    function formatDuration(seconds) {
        if (seconds === null || seconds === undefined)
            return "--"
        var total = Number(seconds)
        if (isNaN(total) || total < 0)
            return "--"
        var hours = Math.floor(total / 3600)
        var minutes = Math.round((total % 3600) / 60)
        if (minutes === 60) {
            hours += 1
            minutes = 0
        }
        return hours > 0 ? hours + "h " + minutes + "m" : minutes + "m"
    }

    function sleepDuration() {
        var current = healthCurrent()
        return current && current.sleep ? formatDuration(current.sleep.total_sleep_seconds) : "--"
    }

    function hasSleepData() {
        var current = healthCurrent()
        return current && current.sleep && current.sleep.total_sleep_seconds !== null
            && current.sleep.total_sleep_seconds !== undefined
    }

    function sleepHeadline() {
        var current = healthCurrent()
        if (!current || !current.sleep)
            return "--"
        var duration = sleepDuration()
        var score = metricNumber(current.sleep.score)
        return duration + (score >= 0 ? " · " + numberText(score, 0) : "")
    }

    function sleepStageModel() {
        var current = healthCurrent()
        var stages = current && current.sleep && current.sleep.stages ? current.sleep.stages : []
        var colors = { awake: "#53615c", light: "#1c8a68", deep: "#2ec79a", rem: "#24745f" }
        var order = ["deep", "light", "rem", "awake"]
        var result = []
        for (var i = 0; i < order.length; i++) {
            for (var j = 0; j < stages.length; j++) {
                if (String(stages[j].stage).toLowerCase() === order[i] && Number(stages[j].seconds) > 0) {
                    result.push({
                        stage: order[i],
                        percentage: Number(stages[j].percentage),
                        color: colors[order[i]],
                        label: order[i].toUpperCase() + " " + formatDuration(stages[j].seconds).toUpperCase()
                    })
                }
            }
        }
        return result
    }

    function healthMetricCards() {
        var current = healthCurrent()
        if (!current)
            return [
                { value: "--", label: "SLEEP HRV", available: false },
                { value: "--", label: "RESTING HR", available: false },
                { value: "--", label: "TEMP DELTA", available: false },
                { value: "--", label: "SPO2", available: false }
            ]
        var recovery = current.recovery || {}
        var hrv = metricNumber(recovery.average_sleep_hrv || current.average_hrv)
        var rhr = metricNumber(recovery.sleep_resting_hr || current.resting_heart_rate)
        var temperatureMetric = recovery.temperature_deviation
        var temperature = metricNumber(temperatureMetric)
        var spo2 = metricNumber(current.spo2)
        return [
            { value: numberText(hrv, 0) + (hrv >= 0 ? " ms" : ""), label: "SLEEP HRV", available: hrv >= 0 },
            { value: numberText(rhr, 0) + (rhr >= 0 ? " bpm" : ""), label: "RESTING HR", available: rhr >= 0 },
            { value: (temperature > 0 ? "+" : "") + numberText(temperature, 1) + (!isNaN(temperature) ? "°" : ""), label: "TEMP DELTA", available: !isNaN(temperature) },
            { value: numberText(spo2, 0) + (spo2 >= 0 ? "%" : ""), label: "SPO2", available: spo2 >= 0 }
        ]
    }

    function heartChartPoints() {
        if (healthRangeDays === 7) {
            var daily = health && health.daily ? health.daily : []
            var result = []
            for (var i = 0; i < daily.length; i++) {
                var value = metricNumber(daily[i].latest_heart_rate)
                if (value >= 0)
                    result.push({ value: value, local_time: daily[i].local_date, unit: "bpm" })
            }
            return result
        }
        var current = healthCurrent()
        return current && current.series && current.series.hr ? current.series.hr : []
    }

    function pointTime(point) {
        if (!point || !point.local_time)
            return ""
        var date = new Date(point.local_time)
        if (isNaN(date.getTime()))
            return String(point.local_time)
        if (healthRangeDays === 7)
            return date.toLocaleDateString(Qt.locale(), "ddd d")
        return date.toLocaleTimeString(Qt.locale(), "HH:mm")
    }

    function chartPointLabel(point) {
        return point ? pointTime(point) + " · " + numberText(Number(point.value), 0) + " BPM" : ""
    }

    function chartAxisLabel(points) {
        if (!points || points.length < 2)
            return ""
        return pointTime(points[0]) + "                                      "
            + pointTime(points[Math.floor(points.length / 2)]) + "                                      "
            + pointTime(points[points.length - 1])
    }

    function heartChartSummary() {
        var points = heartChartPoints()
        if (!points || points.length < 2)
            return "Heart rate chart unavailable"
        var low = Number(points[0].value)
        var high = low
        for (var i = 1; i < points.length; i++) {
            low = Math.min(low, Number(points[i].value))
            high = Math.max(high, Number(points[i].value))
        }
        return "Heart rate chart with " + points.length + " measurements, from "
            + numberText(low, 0) + " to " + numberText(high, 0) + " beats per minute"
    }

    function healthConnected() {
        return !!(health && health.sync && health.sync.connected)
    }

    function syncTime(value) {
        if (!value)
            return "UNAVAILABLE"
        var date = new Date(value)
        return isNaN(date.getTime()) ? "UNAVAILABLE" : date.toLocaleTimeString(Qt.locale(), "HH:mm")
    }

    function weatherLabel() {
        return "24° CLEAR"
    }

    function greetingText() {
        var hour = new Date().getHours()
        var period = hour < 12 ? "morning" : hour < 17 ? "afternoon" : "evening"
        return "Good " + period + ", " + (userName || "Dushyant") + "."
    }

    function summaryText() {
        var devices = allDevices()
        if (!backendOnline)
            return "Backend offline · controls will reconnect automatically."
        var sync = realtimeConnected ? "live" : "syncing"
        var recovery = recoveryScore()
        return activeDeviceCount(devices) + " of " + devices.length + " devices on · " + sync
            + (recovery >= 0 ? " · recovery " + numberText(recovery, 0) : "") + "."
    }

    function healthSyncLabel() {
        if (healthLoading && !healthCurrent())
            return "ULTRAHUMAN RING · SYNCING"
        if (!health || !health.sync)
            return "ULTRAHUMAN RING · WAITING FOR SYNC"
        if (!health.sync.configured)
            return "ULTRAHUMAN RING · NOT CONFIGURED"
        if (health.sync.cached)
            return "ULTRAHUMAN RING · CACHED · SYNC " + syncTime(health.sync.last_successful_sync_at)
        if (!health.sync.connected)
            return "ULTRAHUMAN RING · SYNC UNAVAILABLE"
        return "ULTRAHUMAN RING · LATEST " + syncTime(health.sync.latest_source_at)
    }

    function ultrahumanSubtitle() {
        if (!health || !health.sync || !health.sync.configured)
            return "SERVER CREDENTIALS NOT CONFIGURED"
        if (!health.sync.connected)
            return String(health.sync.message || "SYNC UNAVAILABLE").toUpperCase()
        return (health.sync.cached ? "CACHED · " : "")
            + "LAST SYNC " + syncTime(health.sync.last_successful_sync_at)
    }

    function jarvisStateLabel() {
        if (!wakeWordEnabled)
            return "● MUTED"
        if (voicePipelineActive)
            return "● " + String(assistantStatus || "LISTENING").toUpperCase()
        return "● LISTENING"
    }

    function jarvisPrompt() {
        if (assistantMessage && assistantMessage !== "waiting for wake-word" && voicePipelineActive)
            return assistantMessage
        return "\"Jarvis, how did I sleep — and switch off the bedroom sockets\""
    }

    function jarvisReply() {
        if (!wakeWordEnabled)
            return "Wake word detection is muted. Enable it in Settings to speak with Jarvis."
        if (assistantStatus === "error" || assistantStatus === "command_error")
            return assistantMessage || "I could not complete that command."
        if (assistantMessage && assistantMessage !== "waiting for wake-word" && assistantStatus === "done")
            return assistantMessage
        if (voicePipelineActive)
            return "Listening for your command."
        if (!hasSleepData())
            return "Ring sleep data is unavailable. Switching off the bedroom sockets."
        var recovery = recoveryScore()
        return "You slept " + sleepDuration()
            + (recovery >= 0 ? ", recovery " + numberText(recovery, 0) : "")
            + ". Switching off the bedroom sockets."
    }

    function systemLabel() {
        var model = systemInfo && systemInfo.raspberry_pi_model ? systemInfo.raspberry_pi_model : "RASPBERRY PI"
        return "VOKRR OS 0.4.1 · " + String(model).toUpperCase()
    }

    function apiHost() {
        return String(apiBase).replace(/^https?:\/\//, "").replace(/\/$/, "")
    }

    function homeAssistantSubtitle() {
        return apiHost() + " · " + allDevices().length + " ENTITIES"
    }

    function deviceColor(device) {
        if (!device || !device.state)
            return Qt.rgba(1, 0.96, 0.82, 1)
        var rgb = device.state.rgb_color
        if (rgb && rgb.length === 3)
            return Qt.rgba(Number(rgb[0]) / 255, Number(rgb[1]) / 255, Number(rgb[2]) / 255, 1)
        var kelvin = Number(device.state.color_temp_kelvin || 4000)
        if (kelvin <= 3200)
            return Qt.rgba(1, 0.68, 0.35, 1)
        if (kelvin >= 5500)
            return Qt.rgba(0.76, 0.87, 1, 1)
        return Qt.rgba(1, 0.95, 0.79, 1)
    }

    function colorOptions(device) {
        var whites = [
            { label: "WARM", color: "#ffad59", kelvin: 2700, rgb: [255, 173, 89] },
            { label: "NTRL", color: "#fff2c9", kelvin: 4000, rgb: [255, 242, 201] },
            { label: "COOL", color: "#c8e1ff", kelvin: 6500, rgb: [200, 225, 255] }
        ]
        if (!hasCapability(device, "color"))
            return whites
        return whites.concat([
            { label: "RED", color: "#ff5f56", rgb: [255, 95, 86] },
            { label: "GREEN", color: "#42d392", rgb: [66, 211, 146] },
            { label: "BLUE", color: "#5b8cff", rgb: [91, 140, 255] },
            { label: "VIOLET", color: "#a879ff", rgb: [168, 121, 255] },
            { label: "PINK", color: "#ff74b8", rgb: [255, 116, 184] }
        ])
    }

    function colorDistance(a, b) {
        var dr = Number(a[0]) - Number(b[0])
        var dg = Number(a[1]) - Number(b[1])
        var db = Number(a[2]) - Number(b[2])
        return dr * dr + dg * dg + db * db
    }

    function colorOptionSelected(device, option) {
        if (!device || !device.state)
            return false
        if (device.state.rgb_color && option.rgb)
            return colorDistance(device.state.rgb_color, option.rgb) < 900
        if (device.state.color_temp_kelvin && option.kelvin)
            return Math.abs(Number(device.state.color_temp_kelvin) - option.kelvin) < 650
        return false
    }

    function colorName(device) {
        var options = colorOptions(device)
        for (var i = 0; i < options.length; i++) {
            if (colorOptionSelected(device, options[i]))
                return options[i].label + " · CURRENT COLOR"
        }
        return "CUSTOM · CURRENT COLOR"
    }

    function openColorPicker(device) {
        selectedColorDevice = device
        if (device && device.state) {
            if (device.state.brightness !== undefined && device.state.brightness !== null)
                paletteBrightness = Math.max(1, Math.min(100, Number(device.state.brightness)))
            else if (device.state.percentage !== undefined && device.state.percentage !== null)
                paletteBrightness = Math.max(1, Math.min(100, Number(device.state.percentage)))
            else
                paletteBrightness = 100
        }
    }

    function applyColor(option) {
        if (!selectedColorDevice || !option)
            return
        var payload
        if (option.kelvin && hasCapability(selectedColorDevice, "color_temperature"))
            payload = { color_temp_kelvin: option.kelvin }
        else
            payload = { rgb_color: option.rgb }
        deviceSetRequested(selectedColorDevice, payload)
        var optimistic = JSON.parse(JSON.stringify(selectedColorDevice))
        optimistic.state = optimistic.state || {}
        if (payload.rgb_color)
            optimistic.state.rgb_color = payload.rgb_color
        if (payload.color_temp_kelvin) {
            optimistic.state.color_temp_kelvin = payload.color_temp_kelvin
            optimistic.state.rgb_color = null
        }
        optimistic.state.is_on = true
        selectedColorDevice = optimistic
    }

    function brightnessFromPosition(position, widthValue) {
        return Math.max(1, Math.min(100, Math.round(position / Math.max(1, widthValue) * 100)))
    }

    function commitBrightness() {
        if (!selectedColorDevice)
            return
        if (hasCapability(selectedColorDevice, "brightness"))
            deviceSetRequested(selectedColorDevice, { brightness: Math.round(paletteBrightness) })
        else if (hasCapability(selectedColorDevice, "percentage"))
            deviceSetRequested(selectedColorDevice, { percentage: Math.round(paletteBrightness) })
    }
}
