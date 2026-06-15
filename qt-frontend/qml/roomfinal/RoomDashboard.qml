import QtQuick
import "../components" as VokrrComponents

Item {
    id: root

    property var rooms: []
    property int currentRoomIndex: 0
    property string timeText: ""
    property string dateText: ""
    property bool mediaConnected: false
    property bool mediaPlaying: false
    property string mediaTitle: ""
    property string mediaArtist: ""
    property string mediaAlbum: ""
    property string mediaArtUrl: ""
    property bool darkMode: true
    property bool voicePipelineActive: false
    property string voiceStatusText: voicePipelineActive ? "waiting for command" : "waiting for wake-word"
    signal roomSelected(string roomId)
    signal deviceActionRequested(var device)
    signal deviceSetRequested(var device, var payload)
    signal mediaActionRequested(string action)
    signal themeModeRequested(bool darkMode)

    ThemeTokens {
        id: theme
        darkMode: root.darkMode
    }

    readonly property var dashboardTheme: theme

    Rectangle {
        anchors.fill: parent
        color: theme.bgApp
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: Math.min(172, parent.height * 0.4)
        opacity: theme.darkMode ? 0.55 : 0.8
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0; color: theme.darkMode ? "#202426" : "#FFFFFFFF" }
            GradientStop { position: 1; color: theme.bgApp }
        }
    }

    readonly property var effectiveRooms: rooms && rooms.length ? rooms : []
    readonly property int safeRoomIndex: Math.max(0, Math.min(currentRoomIndex, Math.max(0, effectiveRooms.length - 1)))
    readonly property var selectedRoom: effectiveRooms.length ? effectiveRooms[safeRoomIndex] : null
    readonly property var selectedDevices: normalizeDevices(selectedRoom && selectedRoom.devices ? selectedRoom.devices : [])
    readonly property real contentLeft: width >= 760 ? 88 : 78
    readonly property real contentRight: 16
    readonly property real contentTop: 12
    readonly property real contentWidth: Math.max(420, width - contentLeft - contentRight)
    readonly property bool sideRailVisible: contentWidth >= 620
    readonly property real gap: 10
    readonly property real sideWidth: sideRailVisible ? Math.min(198, Math.max(178, contentWidth * 0.28)) : 0
    readonly property real gridWidth: sideRailVisible ? contentWidth - sideWidth - gap : contentWidth
    readonly property real headerHeight: 62
    readonly property real mainTop: contentTop + headerHeight + 10
    readonly property real bottomMargin: 14
    readonly property real mainHeight: Math.max(280, height - mainTop - bottomMargin)
    readonly property int gridColumns: Math.max(2, Math.min(3, Math.floor((gridWidth + gap) / 158)))
    readonly property real cardWidth: Math.floor((gridWidth - gap * (gridColumns - 1)) / gridColumns)
    readonly property real cardHeight: sideRailVisible ? 130 : 126
    readonly property bool compactHeader: contentWidth < 650
    readonly property real titleBlockWidth: compactHeader ? 82 : 98
    readonly property real timePanelWidth: compactHeader ? 92 : 104
    readonly property real togglePanelWidth: 68
    readonly property real voicePanelWidth: compactHeader ? 0 : 132
    readonly property real headerGapCount: compactHeader ? 3 : 4
    readonly property real roomSelectorWidth: Math.max(188, contentWidth - titleBlockWidth - timePanelWidth - togglePanelWidth - voicePanelWidth - gap * headerGapCount)

    Component.onCompleted: updateClock()

    Timer {
        running: true
        repeat: true
        interval: 30000
        onTriggered: root.updateClock()
    }

    Row {
        id: headerRow
        x: root.contentLeft
        y: root.contentTop
        width: root.contentWidth
        height: root.headerHeight
        spacing: root.gap

        Item {
            width: root.titleBlockWidth
            height: parent.height

            Text {
                x: 0
                y: 5
                width: parent.width
                text: "Home"
                color: theme.textPrimary
                font.family: theme.family()
                font.pixelSize: 26
                font.bold: true
                elide: Text.ElideRight
            }

            Text {
                x: 1
                y: 38
                width: parent.width
                text: activeDeviceCount() + " active"
                color: theme.textMuted
                font.family: theme.family()
                font.pixelSize: 11
                font.bold: true
                elide: Text.ElideRight
            }
        }

        GlassPanel {
            width: root.roomSelectorWidth
            height: 52
            y: 4
            theme: root.dashboardTheme
            radius: theme.radiusLg
            padding: 0
            active: true

            VokrrComponents.Button {
                x: 4
                y: 4
                width: 38
                height: 38
                variant: "ghost"
                darkMode: theme.darkMode
                enabled: root.effectiveRooms.length > 1
                opacity: enabled ? 1 : 0.35

                SvgIcon {
                    anchors.centerIn: parent
                    width: 18
                    height: 18
                    name: "chevron-left"
                    darkMode: theme.darkMode
                }

                onClicked: root.moveRoom(-1)
            }

            SvgIcon {
                x: 48
                y: 15
                width: 20
                height: 20
                name: "house"
                darkMode: theme.darkMode
            }

            Column {
                x: 74
                y: 8
                width: parent.width - 118
                spacing: 0

                Text {
                    width: parent.width
                    text: root.roomName()
                    color: theme.textPrimary
                    font.family: theme.family()
                    font.pixelSize: 15
                    font.bold: true
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    text: root.selectedDevices.length + " devices"
                    color: theme.textMuted
                    font.family: theme.family()
                    font.pixelSize: 10
                    font.bold: true
                    elide: Text.ElideRight
                }
            }

            VokrrComponents.Button {
                x: parent.width - 42
                y: 4
                width: 38
                height: 38
                variant: "ghost"
                darkMode: theme.darkMode
                enabled: root.effectiveRooms.length > 1
                opacity: enabled ? 1 : 0.35

                SvgIcon {
                    anchors.centerIn: parent
                    width: 18
                    height: 18
                    name: "chevron-right"
                    darkMode: theme.darkMode
                }

                onClicked: root.moveRoom(1)
            }

            MouseArea {
                anchors.fill: parent
                anchors.leftMargin: 42
                anchors.rightMargin: 42
                property real startX: 0
                onPressed: startX = mouse.x
                onReleased: {
                    var delta = mouse.x - startX
                    if (Math.abs(delta) > 30)
                        root.moveRoom(delta < 0 ? 1 : -1)
                }
            }
        }

        GlassPanel {
            width: root.voicePanelWidth
            height: 52
            y: 4
            visible: !root.compactHeader
            theme: root.dashboardTheme
            radius: theme.radiusLg
            padding: 0
            active: root.voicePipelineActive

            Row {
                anchors.centerIn: parent
                width: parent.width - 18
                spacing: 7

                Rectangle {
                    width: 9
                    height: 9
                    radius: 5
                    color: root.voicePipelineActive ? theme.accentGreen : theme.textDisabled
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    width: parent.width - 16
                    text: root.voiceStatusText
                    color: theme.textPrimary
                    font.family: theme.family()
                    font.pixelSize: 10
                    font.bold: true
                    elide: Text.ElideRight
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        GlassPanel {
            width: root.timePanelWidth
            height: 52
            y: 4
            theme: root.dashboardTheme
            radius: theme.radiusLg
            padding: 0

            Column {
                anchors.centerIn: parent
                width: parent.width
                spacing: 0

                Text {
                    width: parent.width
                    text: root.timeText
                    color: theme.textPrimary
                    font.family: theme.family()
                    font.pixelSize: root.compactHeader ? 13 : 14
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    text: root.dateText
                    color: theme.textMuted
                    font.family: theme.family()
                    font.pixelSize: 10
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }
            }
        }

        ThemeToggle {
            width: root.togglePanelWidth
            height: 26
            y: 17
            theme: root.dashboardTheme
            checked: !theme.darkMode
            onToggled: root.themeModeRequested(!root.darkMode)
        }
    }

    Flickable {
        id: controlsFlick
        x: root.contentLeft
        y: root.mainTop
        width: root.gridWidth
        height: root.mainHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        contentWidth: width
        contentHeight: Math.max(height, deviceGrid.y + deviceGrid.implicitHeight + 8)

        Text {
            x: 1
            y: 0
            text: "Controls"
            color: theme.textPrimary
            font.family: theme.family()
            font.pixelSize: 16
            font.bold: true
        }

        Text {
            x: 78
            y: 4
            width: parent.width - 78
            text: root.selectedDevices.length ? root.selectedDevices.length + " smart devices" : "Waiting for rooms"
            color: theme.textMuted
            font.family: theme.family()
            font.pixelSize: 11
            elide: Text.ElideRight
        }

        Grid {
            id: deviceGrid
            x: 0
            y: 30
            width: parent.width
            columns: root.gridColumns
            rowSpacing: root.gap
            columnSpacing: root.gap

            Repeater {
                model: root.selectedDevices

                DeviceCard {
                    width: root.cardWidth
                    height: root.cardHeight
                    theme: root.dashboardTheme
                    deviceName: modelData.name
                    meta: modelData.meta
                    statusText: modelData.status
                    deviceType: modelData.type
                    deviceActive: modelData.active
                    actionable: modelData.actionable
                    hasLevel: modelData.hasLevel
                    levelValue: modelData.level
                    rawDevice: modelData.raw
                    onActivated: function(rawDevice) { root.deviceActionRequested(rawDevice) }
                    onLevelRequested: function(rawDevice, value) { root.requestLevel(rawDevice, value) }
                }
            }
        }

        GlassPanel {
            x: 0
            y: 30
            width: parent.width
            height: Math.min(160, parent.height - 30)
            visible: root.selectedDevices.length === 0
            theme: root.dashboardTheme
            radius: theme.radiusXl
            padding: 0

            Column {
                anchors.centerIn: parent
                width: parent.width - 40
                spacing: 8

                SvgIcon {
                    width: 28
                    height: 28
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: "house"
                    darkMode: theme.darkMode
                }

                Text {
                    width: parent.width
                    text: root.effectiveRooms.length ? "No devices in this room" : "No Home Assistant rooms"
                    color: theme.textPrimary
                    font.family: theme.family()
                    font.pixelSize: 15
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    text: "Controls appear here after discovery"
                    color: theme.textMuted
                    font.family: theme.family()
                    font.pixelSize: 11
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }
            }
        }
    }

    Column {
        x: root.contentLeft + root.gridWidth + root.gap
        y: root.mainTop
        width: root.sideWidth
        height: root.mainHeight
        spacing: root.gap
        visible: root.sideRailVisible

        RoomSummaryPanel {
            width: parent.width
            height: 134
            theme: root.dashboardTheme
            roomName: root.roomName()
            imageSource: root.roomImageFor(root.selectedRoom)
            activeCount: root.activeDeviceCount()
            deviceCount: root.selectedDevices.length
        }

        WeatherEnvironmentPanel {
            width: parent.width
            height: 126
            theme: root.dashboardTheme
            environment: root.environmentFromDevices(root.selectedDevices)
        }

        MediaPlayerPanel {
            width: parent.width
            height: 82
            theme: root.dashboardTheme
            connected: root.mediaConnected
            playing: root.mediaPlaying
            title: root.mediaTitle
            artist: root.mediaArtist
            album: root.mediaAlbum
            albumArtUrl: root.mediaArtUrl
            onMediaAction: function(action) { root.mediaActionRequested(action) }
        }
    }

    function updateClock() {
        var now = new Date()
        var hours = now.getHours()
        var minutes = now.getMinutes()
        var suffix = hours >= 12 ? "PM" : "AM"
        var hour12 = hours % 12
        if (hour12 === 0)
            hour12 = 12
        timeText = hour12 + ":" + (minutes < 10 ? "0" : "") + minutes + " " + suffix
        var days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        dateText = days[now.getDay()] + ", " + now.getDate() + " " + months[now.getMonth()]
    }

    function roomName() {
        return selectedRoom && selectedRoom.name ? selectedRoom.name : "No Rooms"
    }

    function moveRoom(delta) {
        if (!effectiveRooms || effectiveRooms.length === 0)
            return
        currentRoomIndex = (safeRoomIndex + delta + effectiveRooms.length) % effectiveRooms.length
        if (selectedRoom && selectedRoom.id)
            roomSelected(selectedRoom.id)
    }

    function normalizeDevices(input) {
        var out = []
        for (var i = 0; i < input.length; i++) {
            var device = input[i]
            out.push({
                name: device.name || "Device",
                meta: deviceMeta(device),
                status: statusFor(device),
                type: typeFor(device),
                active: activeFor(device),
                actionable: actionableFor(device),
                hasLevel: hasLevelFor(device),
                level: levelFor(device),
                raw: device
            })
        }
        return out
    }

    function deviceMeta(device) {
        if (!device)
            return "Smart device"
        if (device.room_name && device.type)
            return device.room_name + " - " + device.type
        return device.room_name || device.type || "Smart device"
    }

    function hasCapability(device, capability) {
        return !!(device && device.capabilities && device.capabilities.indexOf(capability) !== -1)
    }

    function typeFor(device) {
        var raw = String((device && ((device.type || "") + " " + (device.entity_id || "") + " " + (device.name || ""))) || "").toLowerCase()
        var klass = String(device && device.state && device.state.attributes && device.state.attributes.device_class ? device.state.attributes.device_class : "").toLowerCase()
        if (raw.indexOf("light") !== -1 || raw.indexOf("tube") !== -1 || raw.indexOf("tubelight") !== -1 || raw.indexOf("bulb") !== -1 || klass.indexOf("light") !== -1)
            return "light"
        if (raw.indexOf("fan") !== -1)
            return "fan"
        if (raw.indexOf("climate") !== -1 || raw.indexOf("ac") !== -1 || raw.indexOf("air conditioner") !== -1)
            return "ac"
        if (raw.indexOf("tv") !== -1 || raw.indexOf("television") !== -1)
            return "tv"
        if (raw.indexOf("camera") !== -1)
            return "camera"
        if (raw.indexOf("cover") !== -1 || raw.indexOf("curtain") !== -1 || raw.indexOf("blind") !== -1)
            return "curtain"
        if (raw.indexOf("speaker") !== -1 || raw.indexOf("media") !== -1 || raw.indexOf("sound") !== -1)
            return "speaker"
        if (raw.indexOf("purifier") !== -1)
            return "purifier"
        if (raw.indexOf("weather") !== -1)
            return "weather"
        if (raw.indexOf("plug") !== -1 || raw.indexOf("socket") !== -1 || raw.indexOf("outlet") !== -1)
            return "plug"
        if (raw.indexOf("sensor") !== -1 || klass.length > 0)
            return "sensor"
        return "switch"
    }

    function activeFor(device) {
        if (device && device.active !== undefined)
            return device.active
        return !!(device && device.state && device.state.is_on)
    }

    function actionableFor(device) {
        if (!device)
            return false
        if (!device.state || device.state.state === "unknown" || device.state.state === "unavailable" || device.state.state === "offline" || device.state.state === "unreachable")
            return false
        return hasCapability(device, "toggle")
            || hasCapability(device, "brightness")
            || hasCapability(device, "percentage")
            || hasCapability(device, "color_temperature")
            || hasCapability(device, "color")
    }

    function statusFor(device) {
        if (device && device.status)
            return device.status
        if (device && device.state) {
            if (device.state.is_on === false)
                return "Off"
            if (device.state.brightness !== undefined && device.state.brightness !== null)
                return Math.round(device.state.brightness) + "%"
            if (device.state.percentage !== undefined && device.state.percentage !== null)
                return Math.round(device.state.percentage) + "%"
            if (device.state.temperature !== undefined && device.state.temperature !== null)
                return Math.round(device.state.temperature) + "°C"
            return device.state.is_on ? "On" : "Off"
        }
        return "Ready"
    }

    function hasLevelFor(device) {
        return !!(device && device.state && (hasCapability(device, "brightness") || hasCapability(device, "percentage") || device.state.brightness !== undefined || device.state.percentage !== undefined))
    }

    function levelFor(device) {
        if (!device || !device.state)
            return 0
        if (device.state.brightness !== undefined && device.state.brightness !== null)
            return Math.max(0, Math.min(100, Number(device.state.brightness)))
        if (device.state.percentage !== undefined && device.state.percentage !== null)
            return Math.max(0, Math.min(100, Number(device.state.percentage)))
        return device.state.is_on ? 100 : 0
    }

    function requestLevel(device, value) {
        if (!device)
            return
        if (hasCapability(device, "brightness") || (device.state && device.state.brightness !== undefined)) {
            deviceSetRequested(device, { brightness: value })
            return
        }
        deviceSetRequested(device, { percentage: value })
    }

    function activeDeviceCount() {
        var count = 0
        for (var i = 0; i < selectedDevices.length; i++) {
            if (selectedDevices[i].active)
                count++
        }
        return count
    }

    function countActive(typeName) {
        var count = 0
        for (var i = 0; i < selectedDevices.length; i++) {
            if (selectedDevices[i].type === typeName && selectedDevices[i].active)
                count++
        }
        return count
    }

    function environmentFromDevices(devices) {
        var env = {}
        for (var i = 0; i < devices.length; i++) {
            var raw = devices[i].raw || {}
            var typeName = devices[i].type
            var name = String(raw.name || raw.entity_id || "").toLowerCase()
            var attrs = raw.state && raw.state.attributes ? raw.state.attributes : {}
            var deviceClass = String(attrs.device_class || "").toLowerCase()
            var unit = String(attrs.unit_of_measurement || "").toLowerCase()
            var value = raw.state && raw.state.state !== undefined ? raw.state.state : null
            if (!env.temperature && (deviceClass === "temperature" || unit.indexOf("°") !== -1 || name.indexOf("temperature") !== -1))
                env.temperature = value + (String(value).indexOf("°") === -1 ? "°C" : "")
            if (!env.humidity && (deviceClass === "humidity" || unit === "%" || name.indexOf("humidity") !== -1))
                env.humidity = value + (String(value).indexOf("%") === -1 ? "%" : "")
            if (!env.aqi && (name.indexOf("aqi") !== -1 || name.indexOf("air quality") !== -1))
                env.aqi = "AQI " + value
            if (!env.condition && (typeName === "weather" || name.indexOf("weather") !== -1))
                env.condition = String(value || attrs.condition || "")
        }
        return env
    }

    function roomImageFor(room) {
        var name = String(room && room.name ? room.name : "").toLowerCase()
        if (name.indexOf("bath") !== -1)
            return "qrc:/assets/images/bathroom.jpg"
        if (name.indexOf("bed") !== -1)
            return "qrc:/assets/images/bedroom.jpg"
        if (name.indexOf("dining") !== -1)
            return "qrc:/assets/images/dining_room.jpg"
        if (name.indexOf("gaming") !== -1 || name.indexOf("game") !== -1)
            return "qrc:/assets/images/gaming_room.jpg"
        if (name.indexOf("kitchen") !== -1)
            return "qrc:/assets/images/kitchen.jpg"
        if (name.indexOf("living") !== -1 || name.indexOf("hall") !== -1 || name.indexOf("lounge") !== -1)
            return "qrc:/assets/images/living_room.jpg"
        return "qrc:/assets/images/room-" + ((Math.max(0, root.safeRoomIndex) % 3) + 1) + ".jpg"
    }

    component RoomSummaryPanel: GlassPanel {
        id: summary

        property string roomName: ""
        property string imageSource: ""
        property int activeCount: 0
        property int deviceCount: 0

        radius: theme.radiusXl
        padding: 0
        active: activeCount > 0
        clip: true

        Image {
            anchors.fill: parent
            source: summary.imageSource
            fillMode: Image.PreserveAspectCrop
            opacity: theme.darkMode ? 0.42 : 0.68
            asynchronous: true
            smooth: true
        }

        Rectangle {
            anchors.fill: parent
            color: theme.darkMode ? "#99111113" : "#45FFFFFF"
        }

        Column {
            x: 14
            y: 14
            width: parent.width - 28
            spacing: 4

            Text {
                width: parent.width
                text: summary.roomName
                color: theme.textPrimary
                font.family: theme.family()
                font.pixelSize: 17
                font.bold: true
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                text: summary.activeCount + " active of " + summary.deviceCount
                color: theme.textSecondary
                font.family: theme.family()
                font.pixelSize: 11
                font.bold: true
                elide: Text.ElideRight
            }
        }

        Row {
            x: 14
            y: parent.height - 42
            spacing: 8

            Repeater {
                model: [
                    { icon: "lightbulb", value: root.countActive("light") },
                    { icon: "fan", value: root.countActive("fan") },
                    { icon: "plug", value: root.countActive("plug") + root.countActive("switch") }
                ]

                Rectangle {
                    width: 46
                    height: 28
                    radius: 14
                    color: theme.darkMode ? "#33FFFFFF" : "#CCFFFFFF"
                    border.width: 1
                    border.color: theme.darkMode ? "#24FFFFFF" : "#80FFFFFF"

                    SvgIcon {
                        x: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: 14
                        height: 14
                        name: modelData.icon
                        darkMode: theme.darkMode
                    }

                    Text {
                        x: 26
                        width: 16
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.value
                        color: theme.textPrimary
                        font.family: theme.family()
                        font.pixelSize: 11
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }
        }
    }
}
