import QtQuick

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
    signal mediaActionRequested(string action)
    signal themeModeRequested(bool darkMode)

    ThemeTokens {
        id: theme
        darkMode: root.darkMode
    }

    Rectangle {
        anchors.fill: parent
        color: theme.bgApp
    }

    Canvas {
        id: glow
        anchors.fill: parent
        antialiasing: true
        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            var gradient = ctx.createRadialGradient(width * 0.76, height * 0.14, 0, width * 0.76, height * 0.14, width * 0.38)
            gradient.addColorStop(0, theme.appGlow)
            gradient.addColorStop(1, "transparent")
            ctx.fillStyle = gradient
            ctx.fillRect(0, 0, width, height)
        }
        Connections {
            target: theme
            function onDarkModeChanged() { glow.requestPaint() }
        }
    }

    readonly property var effectiveRooms: rooms && rooms.length ? rooms : []
    readonly property var selectedRoom: effectiveRooms.length ? effectiveRooms[Math.max(0, Math.min(currentRoomIndex, effectiveRooms.length - 1))] : null
    readonly property var selectedDevices: normalizeDevices(selectedRoom && selectedRoom.devices ? selectedRoom.devices : [])
    readonly property real designWidth: 640
    readonly property real designHeight: 480
    readonly property real scaleFactor: Math.max(1, Math.min(width / designWidth, height / designHeight))
    readonly property real contentX: Math.max(84, Math.round(width * 0.13))
    readonly property real contentRightMargin: 14
    readonly property real contentGap: 8 * scaleFactor
    readonly property real contentWidth: Math.max(420, width - contentX - contentRightMargin)
    readonly property real rightColumnWidth: Math.max(184, Math.min(260, contentWidth * 0.34))
    readonly property real leftColumnWidth: Math.max(300, contentWidth - rightColumnWidth - contentGap)
    readonly property real topMargin: 12
    readonly property real headerHeight: 56
    readonly property real mainTop: topMargin + headerHeight + 8
    readonly property real bottomMargin: 12
    readonly property real mediaHeight: 74
    readonly property real mediaTop: height - bottomMargin - mediaHeight
    readonly property real weatherHeight: Math.min(132, Math.max(112, (mediaTop - mainTop - contentGap * 2) * 0.32))
    readonly property real cameraTop: mainTop + weatherHeight + contentGap
    readonly property real cameraHeight: Math.max(120, mediaTop - cameraTop - contentGap)
    readonly property real heroHeight: Math.max(180, Math.min(260, height * 0.46))
    readonly property real pagerTop: mainTop + heroHeight + contentGap
    readonly property real pagerHeight: Math.max(150, height - pagerTop - bottomMargin)

    Component.onCompleted: updateClock()

    Timer {
        running: true
        repeat: true
        interval: 30000
        onTriggered: root.updateClock()
    }

    function updateClock() {
        var now = new Date()
        var hours = now.getHours()
        var minutes = now.getMinutes()
        var suffix = hours >= 12 ? "PM" : "AM"
        var hour12 = hours % 12
        if (hour12 === 0)
            hour12 = 12
        timeText = (hour12 < 10 ? "0" : "") + hour12 + ":" + (minutes < 10 ? "0" : "") + minutes + " " + suffix
        var days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        dateText = days[now.getDay()] + ", " + now.getDate() + " " + months[now.getMonth()]
    }

    function setRoomIndex(index) {
        currentRoomIndex = Math.max(0, Math.min(index, effectiveRooms.length - 1))
        if (selectedRoom && selectedRoom.id)
            roomSelected(selectedRoom.id)
    }

    function normalizeDevices(input) {
        var out = []
        for (var i = 0; i < input.length; i++) {
            var device = input[i]
            out.push({
                name: device.name || "Device",
                meta: device.meta || device.type || device.room_name || "Smart device",
                status: statusFor(device),
                type: typeFor(device),
                active: activeFor(device),
                actionable: actionableFor(device),
                raw: device
            })
        }
        return out
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
        var typeName = typeFor(device)
        return !!device.state || typeName === "switch" || typeName === "light" || typeName === "fan" || typeName === "ac" || typeName === "speaker" || typeName === "camera"
    }

    function statusFor(device) {
        if (device && device.status)
            return device.status
        if (device && device.state) {
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

    function camerasFor(devices) {
        var out = []
        for (var i = 0; i < devices.length; i++) {
            if (devices[i].type === "camera")
                out.push({ name: devices[i].name, status: devices[i].active ? "Live" : "Offline" })
        }
        return out
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
        return "qrc:/assets/images/room-" + ((Math.max(0, root.currentRoomIndex) % 3) + 1) + ".jpg"
    }

    RoomHeader {
        x: root.contentX
        y: root.topMargin
        width: root.contentWidth
        height: root.headerHeight
        theme: theme
        rooms: root.effectiveRooms
        currentRoomIndex: root.currentRoomIndex
        deviceCount: root.selectedDevices.length
        timeText: root.timeText
        dateText: root.dateText
        voicePipelineActive: root.voicePipelineActive
        voiceStatusText: root.voiceStatusText
        onRoomSelected: function(index) { root.setRoomIndex(index) }
        onThemeRequested: root.themeModeRequested(!root.darkMode)
    }

    RoomHeroPanel {
        x: root.contentX
        y: root.mainTop
        width: root.leftColumnWidth
        height: root.heroHeight
        theme: theme
        roomName: root.selectedRoom && root.selectedRoom.name ? root.selectedRoom.name : "No Room"
        roomImageSource: root.roomImageFor(root.selectedRoom)
        devices: root.selectedDevices
    }

    WeatherEnvironmentPanel {
        x: root.contentX + root.leftColumnWidth + root.contentGap
        y: root.mainTop
        width: root.rightColumnWidth
        height: root.weatherHeight
        theme: theme
        environment: root.environmentFromDevices(root.selectedDevices)
    }

    CameraLivePanel {
        x: root.contentX + root.leftColumnWidth + root.contentGap
        y: root.cameraTop
        width: root.rightColumnWidth
        height: root.cameraHeight
        theme: theme
        cameras: root.camerasFor(root.selectedDevices)
    }

    DevicePager {
        x: root.contentX
        y: root.pagerTop
        width: root.leftColumnWidth
        height: root.pagerHeight
        theme: theme
        roomId: root.selectedRoom && root.selectedRoom.id ? root.selectedRoom.id : ""
        devices: root.selectedDevices
        onDeviceActivated: function(rawDevice) { root.deviceActionRequested(rawDevice) }
    }

    MediaPlayerPanel {
        x: root.contentX + root.leftColumnWidth + root.contentGap
        y: root.mediaTop
        width: root.rightColumnWidth
        height: root.mediaHeight
        theme: theme
        connected: root.mediaConnected
        playing: root.mediaPlaying
        title: root.mediaTitle
        artist: root.mediaArtist
        album: root.mediaAlbum
        albumArtUrl: root.mediaArtUrl
        onMediaAction: function(action) { root.mediaActionRequested(action) }
    }
}
