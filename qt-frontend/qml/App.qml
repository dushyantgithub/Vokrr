import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtWebSockets

ApplicationWindow {
    id: app
    visible: true
    width: 800
    height: 480
    minimumWidth: 800
    minimumHeight: 480
    title: "Vokrr"
    color: "#071014"

    property string apiBase: vokrrBackendApiBase || "http://localhost:8080"
    property string token: ""
    property string refreshToken: ""
    property var currentUser: null
    property var rooms: []
    property var scenes: []
    property var health: null
    property string healthError: ""
    property string activeView: "Dashboard"
    property string selectedRoomId: ""
    property string assistantStatus: "idle"
    property string assistantMessage: "Say Jarvis to start"
    property var notifications: []
    property string loginError: ""
    property bool loading: true
    property bool devicesRefreshing: false
    property var networkStatus: null
    property string networkError: ""

    readonly property var navItems: [
        { key: "Dashboard", label: "Dashboard", icon: "H" },
        { key: "Devices", label: "Devices", icon: "D" },
        { key: "Routines", label: "Routines", icon: "R" },
        { key: "Activity", label: "Activity", icon: "A" },
        { key: "Settings", label: "Settings", icon: "S" }
    ]
    readonly property var statusLabels: ({
        idle: "Waiting for Jarvis",
        listening: "Listening",
        processing: "Processing",
        done: "Ready",
        error: "Error",
        command_error: "Command failed"
    })

    function hasCapability(device, capability) {
        return device && device.capabilities && device.capabilities.indexOf(capability) !== -1
    }

    function websocketUrl() {
        var base = apiBase
        if (base.indexOf("https://") === 0)
            return "wss://" + base.slice(8) + "/ws?token=" + encodeURIComponent(token)
        if (base.indexOf("http://") === 0)
            return "ws://" + base.slice(7) + "/ws?token=" + encodeURIComponent(token)
        return "ws://localhost:8080/ws?token=" + encodeURIComponent(token)
    }

    function allDevices() {
        var list = []
        for (var i = 0; i < rooms.length; i++) {
            var devices = rooms[i].devices || []
            for (var j = 0; j < devices.length; j++)
                list.push(devices[j])
        }
        return list
    }

    function selectedRoom() {
        if (!rooms.length)
            return null
        for (var i = 0; i < rooms.length; i++) {
            if (rooms[i].id === selectedRoomId)
                return rooms[i]
        }
        return rooms[0]
    }

    function heroDevice() {
        var room = selectedRoom()
        var candidates = room && room.devices && room.devices.length ? room.devices : allDevices()
        if (!candidates.length)
            return null
        for (var i = 0; i < candidates.length; i++) {
            if (hasCapability(candidates[i], "brightness") || hasCapability(candidates[i], "percentage"))
                return candidates[i]
        }
        return candidates[0]
    }

    function deviceStateLabel(device) {
        if (!device || !device.state || !device.state.state || device.state.state === "unknown")
            return "Unknown"
        return device.state.is_on ? "On" : device.state.state.charAt(0).toUpperCase() + device.state.state.slice(1)
    }

    function deviceIsKnown(device) {
        return device && device.state && device.state.state && device.state.state !== "unknown" && device.state.state !== "unavailable"
    }

    function deviceAccent(device) {
        if (!deviceIsKnown(device))
            return "#ffd37a"
        return device.state.is_on ? "#65e0b5" : "#b8cbc8"
    }

    function pushNotification(message, level) {
        if (!message)
            return
        var next = notifications.slice()
        next.unshift({ message: message, level: level || "info", createdAt: new Date().toLocaleTimeString() })
        notifications = next.slice(0, 12)
    }

    function http(method, path, body, callback, auth) {
        var xhr = new XMLHttpRequest()
        xhr.open(method, apiBase + path)
        xhr.setRequestHeader("Content-Type", "application/json")
        if (auth !== false && token)
            xhr.setRequestHeader("Authorization", "Bearer " + token)
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return
            var data = null
            try {
                if (xhr.responseText)
                    data = JSON.parse(xhr.responseText)
            } catch (e) {
                data = null
            }
            callback(xhr.status, data)
        }
        xhr.send(body === null || body === undefined ? "" : JSON.stringify(body))
    }

    function kioskLogin() {
        loading = true
        http("POST", "/api/auth/kiosk", null, function(status, data) {
            loading = false
            if (status >= 200 && status < 300 && data && data.access_token) {
                applySession(data)
                return
            }
            loginError = "Kiosk login unavailable. Sign in manually."
        }, false)
    }

    function applySession(data) {
        token = data.access_token || ""
        refreshToken = data.refresh_token || ""
        currentUser = data.user || null
        loginError = ""
        loadSnapshot()
        loadHealth()
        loadNetworkStatus()
        ws.active = true
    }

    function login(username, password) {
        loginError = ""
        http("POST", "/api/auth/login", { username: username, password: password }, function(status, data) {
            if (status >= 200 && status < 300 && data && data.access_token) {
                applySession(data)
            } else {
                loginError = "Username or password is incorrect."
            }
        }, false)
    }

    function logout() {
        ws.active = false
        token = ""
        refreshToken = ""
        currentUser = null
        rooms = []
        scenes = []
        selectedRoomId = ""
        activeView = "Dashboard"
    }

    function loadSnapshot() {
        if (!token)
            return
        http("GET", "/api/rooms", null, function(status, data) {
            if (status >= 200 && status < 300 && data) {
                rooms = data
                if (!selectedRoomId && rooms.length)
                    selectedRoomId = rooms[0].id
            } else {
                pushNotification("Could not load rooms", "error")
            }
        })
        http("GET", "/api/scenes", null, function(status, data) {
            if (status >= 200 && status < 300 && data)
                scenes = data
        })
    }

    function refreshDevicesFromHomeAssistant() {
        if (!token || devicesRefreshing)
            return
        devicesRefreshing = true
        http("POST", "/api/devices/refresh", null, function(status, data) {
            if (status >= 200 && status < 300 && data) {
                rooms = data
                if (!selectedRoomId && rooms.length)
                    selectedRoomId = rooms[0].id
                pushNotification("Devices refreshed", "info")
            } else {
                pushNotification("Could not refresh devices", "error")
            }
            devicesRefreshing = false
        })
    }

    function loadHealth() {
        http("GET", "/api/system/health", null, function(status, data) {
            if (status >= 200 && status < 300 && data) {
                var wasOffline = healthError !== ""
                health = data
                healthError = ""
                if (wasOffline && token)
                    loadSnapshot()
            } else {
                health = null
                healthError = "Backend unavailable"
            }
        }, false)
    }

    function loadNetworkStatus() {
        if (!token)
            return
        http("GET", "/api/system/network", null, function(status, data) {
            if (status >= 200 && status < 300 && data) {
                networkStatus = data
                networkError = ""
            } else {
                networkError = "Could not load network status"
            }
        })
    }

    function connectWifi(networkKey) {
        if (!networkKey)
            return
        networkError = "Connecting..."
        http("POST", "/api/system/network/" + encodeURIComponent(networkKey) + "/connect", null, function(status, data) {
            if (status >= 200 && status < 300 && data) {
                networkStatus = data
                networkError = ""
                loadHealth()
                loadSnapshot()
            } else {
                networkError = "Could not connect to Wi-Fi"
                loadNetworkStatus()
            }
        })
    }

    function mergeDevice(updated) {
        var nextRooms = JSON.parse(JSON.stringify(rooms))
        for (var i = 0; i < nextRooms.length; i++) {
            var devices = nextRooms[i].devices || []
            for (var j = 0; j < devices.length; j++) {
                if (devices[j].id === updated.id)
                    devices[j] = updated
            }
        }
        rooms = nextRooms
    }

    function optimisticToggleDevice(device) {
        if (!device || !device.state)
            return null

        var updated = JSON.parse(JSON.stringify(device))
        updated.state.is_on = !device.state.is_on
        updated.state.state = updated.state.is_on ? "on" : "off"
        mergeDevice(updated)
        return updated
    }

    function toggleDevice(device) {
        if (!device)
            return
        console.log("Toggling device", device.id, device.name)
        var optimistic = optimisticToggleDevice(device)
        http("POST", "/api/devices/" + encodeURIComponent(device.id) + "/toggle", null, function(status, data) {
            if (status >= 200 && status < 300 && data) {
                mergeDevice(data)
                pushNotification(device.name + " updated", "info")
            } else {
                if (optimistic)
                    mergeDevice(device)
                loadSnapshot()
                pushNotification("Device action failed", "error")
            }
        })
    }

    function setDevice(device, payload) {
        if (!device)
            return
        http("POST", "/api/devices/" + encodeURIComponent(device.id) + "/set", payload, function(status, data) {
            if (status >= 200 && status < 300 && data) {
                mergeDevice(data)
                pushNotification(device.name + " updated", "info")
            } else {
                pushNotification("Device action failed", "error")
            }
        })
    }

    function runScene(scene) {
        if (!scene)
            return
        http("POST", "/api/scenes/" + encodeURIComponent(scene.id) + "/run", null, function(status) {
            if (status >= 200 && status < 300) {
                pushNotification(scene.name + " ran", "info")
                loadSnapshot()
            } else {
                pushNotification("Could not run " + scene.name, "error")
            }
        })
    }

    function setAssistant(message, status) {
        assistantStatus = status || "idle"
        assistantMessage = message || statusLabels.idle
        if (assistantStatus === "error" || assistantStatus === "command_error")
            pushNotification(assistantMessage, "error")
    }

    Component.onCompleted: kioskLogin()

    Timer {
        running: token.length > 0
        repeat: true
        interval: 5000
        onTriggered: {
            loadHealth()
            loadNetworkStatus()
        }
    }

    Timer {
        running: token.length === 0 && !loading
        repeat: true
        interval: 5000
        onTriggered: kioskLogin()
    }

    Timer {
        running: token.length > 0
        repeat: true
        interval: 3000
        onTriggered: loadSnapshot()
    }

    WebSocket {
        id: ws
        active: false
        url: app.websocketUrl()
        onTextMessageReceived: function(message) {
            var event = JSON.parse(message)
            if (event.event === "snapshot") {
                rooms = event.payload.rooms || []
                if (!selectedRoomId && rooms.length)
                    selectedRoomId = rooms[0].id
            } else if (event.event === "device.updated") {
                mergeDevice(event.payload)
            } else if (event.event === "voice.command") {
                setAssistant(event.payload.message, event.payload.understood ? "done" : "error")
                if (event.payload.navigate)
                    activeView = event.payload.navigate
            } else if (event.event === "voice.status") {
                setAssistant(event.payload.message, event.payload.status)
            } else if (event.event === "scene.ran") {
                pushNotification(event.payload.name + " ran", "info")
            }
        }
        onStatusChanged: function(status) {
            if (token && status === WebSocket.Error)
                pushNotification("Realtime feed disconnected", "warn")
        }
    }

    GradientBackground {
        anchors.fill: parent
    }

    Loader {
        anchors.fill: parent
        active: false
        sourceComponent: token ? shellComponent : loginComponent
    }

    Loader {
        id: devicesRadarLoader

        property var scannerDevices: allDevices()
        property bool scannerRefreshing: devicesRefreshing

        anchors.fill: parent
        active: activeView === "Devices"
        visible: active
        source: Qt.resolvedUrl("RadarDemoContent.qml")
        z: 5

        onLoaded: {
            item.setDevices(scannerDevices)
            item.refreshing = scannerRefreshing
            item.deviceClicked.connect(function(device) { toggleDevice(device) })
            item.refreshRequested.connect(function() { refreshDevicesFromHomeAssistant() })
        }
        onScannerDevicesChanged: {
            if (item)
                item.setDevices(scannerDevices)
        }
        onScannerRefreshingChanged: {
            if (item)
                item.refreshing = scannerRefreshing
        }
    }

    Loader {
        anchors.fill: parent
        anchors.margins: 18
        anchors.bottomMargin: 88
        active: activeView === "Settings"
        visible: active
        sourceComponent: settingsView
        z: 5
    }

    BottomToolbar {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 16
        width: 188
        height: 54
        z: 10
    }

    Component {
        id: loginComponent
        Rectangle {
            color: "transparent"
            ColumnLayout {
                width: 360
                anchors.centerIn: parent
                spacing: 14
                Text { text: "Vokrr"; color: "white"; font.pixelSize: 44; font.bold: true; Layout.alignment: Qt.AlignHCenter }
                Text { text: loading ? "Starting native console" : "Sign in"; color: "#b8cbc8"; font.pixelSize: 16; Layout.alignment: Qt.AlignHCenter }
                TextField { id: username; placeholderText: "Username"; Layout.fillWidth: true; visible: !loading }
                TextField { id: password; placeholderText: "Password"; echoMode: TextInput.Password; Layout.fillWidth: true; visible: !loading }
                Button { text: "Sign in"; Layout.fillWidth: true; visible: !loading; onClicked: login(username.text, password.text) }
                Button { text: "Try kiosk login"; Layout.fillWidth: true; visible: !loading; onClicked: kioskLogin() }
                Text { text: loginError; color: "#ffaaa5"; wrapMode: Text.WordWrap; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter }
            }
        }
    }

    Component {
        id: shellComponent
        RowLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 10

            Rectangle {
                Layout.preferredWidth: 132
                Layout.fillHeight: true
                radius: 8
                color: "#cc0b1518"
                border.color: "#2e5960"

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 6

                    Text { text: "Vokrr"; color: "white"; font.pixelSize: 22; font.bold: true; Layout.bottomMargin: 4 }

                    Repeater {
                        model: navItems
                        delegate: Button {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 42
                            text: modelData.icon + "  " + modelData.label
                            flat: true
                            highlighted: activeView === modelData.key
                            onClicked: activeView = modelData.key
                        }
                    }

                    Item { Layout.fillHeight: true }
                    Text { text: currentUser ? currentUser.username : "Kiosk"; color: "#b8cbc8"; font.pixelSize: 13; elide: Text.ElideRight; Layout.fillWidth: true }
                    Text { text: currentUser && currentUser.is_admin ? "Admin" : "Local console"; color: "#65e0b5"; font.pixelSize: 12 }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 60
                    radius: 8
                    color: "#bb102025"
                    border.color: "#315c65"

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 10
                        Text { text: activeView; color: "white"; font.pixelSize: 23; font.bold: true; Layout.preferredWidth: 120; elide: Text.ElideRight }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 8
                            color: assistantStatus === "error" || assistantStatus === "command_error" ? "#66313535" : "#3320d0a0"
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 8
                                Rectangle { width: 14; height: 14; radius: 7; color: assistantStatus === "listening" ? "#65e0b5" : "#93a8a5" }
                                ColumnLayout {
                                    spacing: 0
                                    Text { text: statusLabels[assistantStatus] || assistantStatus; color: "#dff7f0"; font.pixelSize: 12; font.bold: true }
                                    Text { text: assistantMessage; color: "#b8cbc8"; font.pixelSize: 12; elide: Text.ElideRight; Layout.fillWidth: true }
                                }
                            }
                        }
                        Text {
                            text: healthError ? "Offline" : (health && health.home_assistant && health.home_assistant.ok ? "Online" : "HA offline")
                            color: health && health.home_assistant && health.home_assistant.ok ? "#65e0b5" : "#ffd37a"
                            font.pixelSize: 14
                        }
                    }
                }

                Loader {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    sourceComponent: activeView === "Dashboard" ? dashboardView
                                   : activeView === "Devices" ? devicesView
                                   : activeView === "Routines" ? routinesView
                                   : activeView === "Activity" ? activityView
                                   : settingsView
                }
            }
        }
    }

    Component {
        id: dashboardView
        ColumnLayout {
            spacing: 8
            Flickable {
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                contentWidth: roomTabs.implicitWidth
                contentHeight: height
                clip: true
                RowLayout {
                    id: roomTabs
                    height: parent.height
                    spacing: 8
                    Repeater {
                        model: rooms
                        delegate: Button {
                            Layout.preferredHeight: 36
                            text: modelData.name
                            highlighted: selectedRoomId === modelData.id
                            onClicked: selectedRoomId = modelData.id
                        }
                    }
                    Item { Layout.preferredWidth: 1 }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 8

                DeviceHero {
                    Layout.preferredWidth: 228
                    Layout.fillHeight: true
                    device: heroDevice()
                }

                DeviceGrid {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    devices: selectedRoom() ? (selectedRoom().devices || []) : []
                }
            }
        }
    }

    Component {
        id: devicesView
        DeviceGrid {
            devices: allDevices()
        }
    }

    Component {
        id: routinesView
        ScrollView {
            clip: true
            GridLayout {
                width: parent.width
                columns: 3
                rowSpacing: 10
                columnSpacing: 10
                Repeater {
                    model: scenes
                    delegate: Button {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 86
                        text: modelData.name
                        onClicked: runScene(modelData)
                    }
                }
            }
        }
    }

    Component {
        id: activityView
        RowLayout {
            spacing: 10
            StatCard { label: "Rooms"; value: String(rooms.length) }
            StatCard { label: "Devices"; value: String(allDevices().length) }
            StatCard { label: "Scenes"; value: String(scenes.length) }
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 8
                color: "#bb102025"
                border.color: "#315c65"
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    Text { text: "Recent"; color: "white"; font.pixelSize: 20; font.bold: true }
                    Repeater {
                        model: notifications
                        delegate: Text {
                            Layout.fillWidth: true
                            text: modelData.createdAt + "  " + modelData.message
                            color: modelData.level === "error" ? "#ffaaa5" : "#b8cbc8"
                            font.pixelSize: 13
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }

    Component {
        id: newsView
        Rectangle {
            radius: 8
            color: "#bb102025"
            border.color: "#315c65"
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 10
                Text { text: "News"; color: "white"; font.pixelSize: 28; font.bold: true }
                Text {
                    Layout.fillWidth: true
                    text: "The native Qt console is running without the old embedded browser proxy. Use the companion app or open worldmonitor.app for the full external news surface."
                    color: "#b8cbc8"
                    wrapMode: Text.WordWrap
                    font.pixelSize: 16
                }
                Text { text: "https://www.worldmonitor.app"; color: "#65e0b5"; font.pixelSize: 18 }
                Item { Layout.fillHeight: true }
            }
        }
    }

    Component {
        id: settingsView
        Rectangle {
            radius: 8
            color: "#bb102025"
            border.color: "#315c65"
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 12
                Text { text: "Settings"; color: "white"; font.pixelSize: 28; font.bold: true }
                Text { text: "Backend: " + apiBase; color: "#b8cbc8"; font.pixelSize: 16 }
                Text { text: "User: " + (currentUser ? currentUser.username : "Kiosk"); color: "#b8cbc8"; font.pixelSize: 16 }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 150
                    radius: 8
                    color: "#99090b12"
                    border.color: "#334155"

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 8

                        Text { text: "Internet"; color: "white"; font.pixelSize: 18; font.bold: true }
                        Text {
                            Layout.fillWidth: true
                            text: networkStatus && networkStatus.connected
                                  ? "Connected to " + networkStatus.ssid
                                  : "Not connected to Wi-Fi"
                            color: networkStatus && networkStatus.connected ? "#65e0b5" : "#ffd37a"
                            font.pixelSize: 15
                            elide: Text.ElideRight
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Repeater {
                                model: networkStatus && networkStatus.configured ? networkStatus.configured : []

                                Button {
                                    Layout.preferredWidth: 180
                                    text: modelData.ssid
                                    enabled: !(networkStatus && networkStatus.connected && networkStatus.ssid === modelData.ssid)
                                    onClicked: connectWifi(modelData.key)
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: networkError
                            visible: networkError !== ""
                            color: networkError === "Connecting..." ? "#b8cbc8" : "#ffaaa5"
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                    }
                }

                Button { text: "Refresh status"; onClicked: { loadSnapshot(); loadHealth(); loadNetworkStatus() } }
                Button { text: "Sign out"; onClicked: logout() }
                Item { Layout.fillHeight: true }
            }
        }
    }

    component StatCard: Rectangle {
        property string label: ""
        property string value: ""
        Layout.preferredWidth: 104
        Layout.fillHeight: true
        radius: 8
        color: "#bb102025"
        border.color: "#315c65"
        ColumnLayout {
            anchors.centerIn: parent
            Text { text: value; color: "white"; font.pixelSize: 34; font.bold: true; Layout.alignment: Qt.AlignHCenter }
            Text { text: label; color: "#b8cbc8"; font.pixelSize: 14; Layout.alignment: Qt.AlignHCenter }
        }
    }

    component DeviceHero: Rectangle {
        property var device: null
        radius: 8
        color: "#bb102025"
        border.color: "#315c65"
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 9
            Text { text: device ? device.name : "No device"; color: "white"; font.pixelSize: 22; font.bold: true; Layout.fillWidth: true; elide: Text.ElideRight; wrapMode: Text.NoWrap }
            Text { text: device ? device.room_name + " - " + device.type : "Waiting for configured devices"; color: "#b8cbc8"; font.pixelSize: 13; Layout.fillWidth: true; elide: Text.ElideRight }
            Item { Layout.fillHeight: true }
            Text { text: deviceStateLabel(device); color: deviceAccent(device); font.pixelSize: 20; font.bold: true }
            Slider {
                Layout.fillWidth: true
                visible: device && (hasCapability(device, "brightness") || hasCapability(device, "percentage"))
                from: 0
                to: 100
                value: device && device.state ? (device.state.brightness !== null && device.state.brightness !== undefined ? device.state.brightness : (device.state.percentage || 0)) : 0
                onMoved: {
                    if (device) {
                        if (hasCapability(device, "brightness"))
                            setDevice(device, { brightness: Math.round(value) })
                        else
                            setDevice(device, { percentage: Math.round(value) })
                    }
                }
            }
            Button { text: device && device.state && device.state.is_on ? "Turn off" : "Turn on"; enabled: device; Layout.fillWidth: true; onClicked: toggleDevice(device) }
        }
    }

    component DeviceGrid: ScrollView {
        property var devices: []
        clip: true
        contentWidth: availableWidth

        Item {
            width: parent.width
            height: Math.max(parent.height, grid.contentHeight)

            Text {
                visible: devices.length === 0
                anchors.centerIn: parent
                text: "No configured devices"
                color: "#b8cbc8"
                font.pixelSize: 16
            }

            GridView {
                id: grid
                anchors.fill: parent
                interactive: false
                model: devices
                cellWidth: Math.max(132, Math.floor(width / Math.max(1, Math.floor(width / 150))))
                cellHeight: 92
                delegate: Rectangle {
                    width: GridView.view.cellWidth - 8
                    height: 84
                    radius: 8
                    color: modelData.state && modelData.state.is_on ? "#4431a987" : "#bb102025"
                    border.color: !deviceIsKnown(modelData) ? "#ffd37a" : (modelData.state && modelData.state.is_on ? "#65e0b5" : "#315c65")
                    TapHandler {
                        acceptedDevices: PointerDevice.TouchScreen | PointerDevice.Mouse | PointerDevice.TouchPad
                        onTapped: toggleDevice(modelData)
                    }
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 3
                        Text { text: modelData.name; color: "white"; font.pixelSize: 15; font.bold: true; Layout.fillWidth: true; elide: Text.ElideRight; wrapMode: Text.NoWrap }
                        Text { text: modelData.room_name; color: "#b8cbc8"; font.pixelSize: 11; Layout.fillWidth: true; elide: Text.ElideRight }
                        Item { Layout.fillHeight: true }
                        Text {
                            text: deviceStateLabel(modelData)
                            color: deviceAccent(modelData)
                            font.pixelSize: 13
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }

    component BottomToolbar: Item {
        id: rootItem

        readonly property var toolbarItems: [
            { key: "Dashboard", icon: "dashboard" },
            { key: "Devices", icon: "devices" },
            { key: "Settings", icon: "settings" }
        ]
        readonly property int itemCount: toolbarItems.length
        readonly property real padding: 3
        readonly property real gap: 2
        readonly property real itemWidth: (toolbarItemsArea.width - gap * (itemCount - 1)) / itemCount

        function activeIndex() {
            for (var i = 0; i < toolbarItems.length; i++) {
                if (toolbarItems[i].key === activeView)
                    return i
            }
            return 0
        }

        Rectangle {
            anchors.fill: parent
            radius: 999
            color: "#2f27272a"
            border.color: "#18ffffff"
            border.width: 1
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: rootItem.padding
            radius: 999
            color: "#1f71717a"
        }

        Item {
            id: contentArea

            objectName: "#mainToolbar"
            anchors.fill: parent
            anchors.margins: rootItem.padding

            Rectangle {
                id: activeIndicator

                width: rootItem.itemWidth
                height: parent.height
                x: (rootItem.itemWidth + rootItem.gap) * rootItem.activeIndex()
                radius: 999
                color: "#1f09090b"
                border.color: "#16ffffff"
                border.width: 1

                Behavior on x {
                    NumberAnimation {
                        duration: 200
                        easing.type: Easing.InOutQuad
                    }
                }
            }

            Row {
                id: toolbarItemsArea

                anchors.fill: parent
                spacing: rootItem.gap
                clip: true

                Repeater {
                    model: rootItem.toolbarItems

                    ToolbarTab {
                        width: rootItem.itemWidth
                        height: toolbarItemsArea.height
                        iconName: modelData.icon
                        selected: activeView === modelData.key
                        onClicked: activeView = modelData.key
                    }
                }
            }
        }
    }

    component ToolbarTab: Item {
        id: toolbarTab

        property string iconName: ""
        property bool selected: false
        signal clicked()

        function iconPath() {
            return "qrc:/assets/icons/tab-" + iconName + (selected ? "-active" : "") + ".svg"
        }

        Rectangle {
            anchors.centerIn: parent
            width: parent.width
            height: parent.height
            radius: 999
            color: pressArea.pressed ? "#14ffffff" : "transparent"
        }

        Image {
            anchors.centerIn: parent
            width: 24
            height: 24
            source: toolbarTab.iconPath()
            fillMode: Image.PreserveAspectFit
            mipmap: true
            smooth: true
        }

        MouseArea {
            id: pressArea
            anchors.fill: parent
            onClicked: toolbarTab.clicked()
        }
    }

    component GradientBackground: Item {
        Rectangle {
            anchors.fill: parent
            color: "#071014"
        }

        Canvas {
            anchors.fill: parent
            antialiasing: true

            onPaint: {
                var ctx = getContext("2d")
                var w = width
                var h = height
                if (w <= 0 || h <= 0)
                    return

                var cx = w * 0.5
                var cy = h * -0.5
                var rx = w * 1.25
                var ry = h * 1.25
                var scaleY = ry / rx

                ctx.clearRect(0, 0, w, h)
                ctx.save()
                ctx.translate(cx, cy)
                ctx.scale(1, scaleY)

                var gradient = ctx.createRadialGradient(0, 0, 0, 0, 0, rx)
                gradient.addColorStop(0, "rgba(99, 102, 241, 0.21)")
                gradient.addColorStop(0.4, "rgba(99, 102, 241, 0.21)")
                gradient.addColorStop(1, "rgba(99, 102, 241, 0)")

                ctx.fillStyle = gradient
                ctx.fillRect(-cx, -cy / scaleY, w, h / scaleY)
                ctx.restore()
            }

            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
        }
    }
}
