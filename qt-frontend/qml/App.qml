import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia
import QtQuick.Shapes
import QtQuick.Effects
import QtWebSockets
import "components" as VokrrComponents

ApplicationWindow {
    id: app
    visible: true
    width: 800
    height: 480
    minimumWidth: 800
    minimumHeight: 480
    title: "Vokrr"
    color: "#212121"

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
    property bool startupLoaderVisible: true
    property string settingsPanel: ""
    property var systemInfo: ({})
    property string toastMessage: ""
    property bool toastVisible: false
    property bool refreshInProgress: false
    property var pendingAuthRetries: []
    property bool spotifyPlaybackActive: true
    property string spotifyTrackTitle: "Glow"
    property string spotifyArtistName: "Echo"
    property string spotifyDeviceName: "Vokrr Home"
    property string spotifyAlbumArtUrl: ""
    property bool spotifyConfigured: false
    property bool spotifyConnected: false
    property bool spotifyNeedsAuth: true
    property bool spotifyLoading: false
    property real spotifyProgress: 0.36
    property int spotifyDurationSeconds: 45
    readonly property int appNavigatorWidth: 64
    readonly property int appNavigatorHeight: 254
    readonly property int appNavigatorLeftMargin: 16
    readonly property int appContentGap: 24
    readonly property int appContentLeftInset: appNavigatorLeftMargin + appNavigatorWidth + appContentGap

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

    function mergeRoomsSnapshot(nextRooms) {
        var incomingRooms = nextRooms || []
        var currentDevices = {}
        for (var i = 0; i < rooms.length; i++) {
            var roomDevices = rooms[i].devices || []
            for (var j = 0; j < roomDevices.length; j++) {
                var current = roomDevices[j]
                if (current && current.id)
                    currentDevices[current.id] = current
            }
        }

        var mergedRooms = []
        for (var roomIndex = 0; roomIndex < incomingRooms.length; roomIndex++) {
            var room = JSON.parse(JSON.stringify(incomingRooms[roomIndex]))
            var devices = room.devices || []
            for (var deviceIndex = 0; deviceIndex < devices.length; deviceIndex++) {
                var incoming = devices[deviceIndex]
                var existing = incoming && incoming.id ? currentDevices[incoming.id] : null
                if (existing && JSON.stringify(existing) === JSON.stringify(incoming))
                    devices[deviceIndex] = existing
            }
            room.devices = devices
            mergedRooms.push(room)
        }

        rooms = mergedRooms
        if (!selectedRoomId && rooms.length)
            selectedRoomId = rooms[0].id
        if (selectedRoomId && !hasRoom(selectedRoomId) && rooms.length)
            selectedRoomId = rooms[0].id
    }

    function hasRoom(roomId) {
        for (var i = 0; i < rooms.length; i++) {
            if (rooms[i].id === roomId)
                return true
        }
        return false
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

    function retryPendingAuthRequests(success) {
        var pending = pendingAuthRetries
        pendingAuthRetries = []
        for (var i = 0; i < pending.length; i++)
            pending[i](success)
    }

    function refreshSession(callback) {
        if (!refreshToken) {
            callback(false)
            return
        }

        pendingAuthRetries.push(callback)
        if (refreshInProgress)
            return

        refreshInProgress = true
        http("POST", "/api/auth/refresh", { refresh_token: refreshToken }, function(status, data) {
            refreshInProgress = false
            if (status >= 200 && status < 300 && data && data.access_token) {
                token = data.access_token || ""
                refreshToken = data.refresh_token || ""
                currentUser = data.user || currentUser
                ws.active = false
                ws.active = true
                retryPendingAuthRequests(true)
            } else {
                logout()
                retryPendingAuthRequests(false)
            }
        }, false, true)
    }

    function http(method, path, body, callback, auth, alreadyRetried) {
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
            if (auth !== false && xhr.status === 401 && refreshToken && !alreadyRetried) {
                refreshSession(function(success) {
                    if (success)
                        http(method, path, body, callback, auth, true)
                    else
                        callback(xhr.status, data)
                })
                return
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
        loadSpotifyStatus()
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
                mergeRoomsSnapshot(data)
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
                mergeRoomsSnapshot(data)
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

    function loadSystemInfo() {
        if (!token)
            return
        http("GET", "/api/system/info", null, function(status, data) {
            if (status >= 200 && status < 300 && data)
                systemInfo = data
            else
                showToast("Could not load system info")
        })
    }

    function showToast(message) {
        toastMessage = message
        toastVisible = true
        toastTimer.restart()
    }

    function spotifyAction(action) {
        if (spotifyNeedsAuth || !spotifyConnected) {
            openSpotifyLogin()
            return
        }
        if (action === "playPause") {
            var target = spotifyPlaybackActive ? "pause" : "play"
            spotifyPlaybackActive = !spotifyPlaybackActive
            http("POST", "/api/spotify/player/" + target, null, function(status) {
                if (status >= 200 && status < 300)
                    loadSpotifyStatus()
                else {
                    spotifyPlaybackActive = !spotifyPlaybackActive
                    showToast("Spotify control failed")
                }
            })
            return
        }
        if (action === "previous" || action === "next") {
            http("POST", "/api/spotify/player/" + action, null, function(status) {
                if (status >= 200 && status < 300)
                    loadSpotifyStatus()
                else
                    showToast("Spotify control failed")
            })
            return
        }
        openSpotifyLogin()
    }

    function loadSpotifyStatus() {
        if (!token || spotifyLoading)
            return
        spotifyLoading = true
        http("GET", "/api/spotify/playback", null, function(status, data) {
            spotifyLoading = false
            if (status >= 200 && status < 300 && data) {
                spotifyConfigured = data.configured || false
                spotifyConnected = data.connected || false
                spotifyNeedsAuth = data.needs_auth || false
                spotifyPlaybackActive = data.is_playing || false
                spotifyTrackTitle = data.title || (spotifyNeedsAuth ? "Connect Spotify" : "Spotify")
                spotifyArtistName = data.artist || ""
                spotifyAlbumArtUrl = data.album_art_url || ""
                spotifyDeviceName = data.device_name || "Spotify"
                spotifyDurationSeconds = Math.max(1, Math.round((data.duration_ms || 45000) / 1000))
                spotifyProgress = Math.max(0, Math.min(1, (data.progress_ms || 0) / Math.max(1, data.duration_ms || 45000)))
            } else {
                spotifyNeedsAuth = true
                spotifyTrackTitle = "Connect Spotify"
                spotifyArtistName = "Tap play to authorize"
            }
        })
    }

    function openSpotifyLogin() {
        if (!token)
            return
        http("GET", "/api/spotify/auth-url", null, function(status, data) {
            if (status >= 200 && status < 300 && data && data.auth_url) {
                Qt.openUrlExternally(data.auth_url)
                showToast("Complete Spotify login in the browser")
            } else {
                showToast("Spotify auth is not ready")
            }
        })
    }

    function spotifyTimeLabel(seconds) {
        var value = Math.max(0, Math.floor(seconds))
        var remainder = value % 60
        return Math.floor(value / 60) + ":" + (remainder < 10 ? "0" : "") + remainder
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
                showToast("Connected")
            } else {
                networkError = "Could not connect to Wi-Fi"
                loadNetworkStatus()
                showToast("Connection failed")
            }
        })
    }

    function openSettingsPanel(panelName) {
        settingsPanel = panelName
        if (panelName === "Network")
            loadNetworkStatus()
        if (panelName === "Information")
            loadSystemInfo()
    }

    function restartRaspberryPi() {
        http("POST", "/api/admin/system/restart", null, function(status, data) {
            if (status >= 200 && status < 300) {
                pushNotification("Raspberry Pi restart requested", "info")
            } else {
                pushNotification("Could not restart Raspberry Pi", "error")
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
        running: true
        repeat: false
        interval: 5000
        onTriggered: startupLoaderVisible = false
    }

    Timer {
        id: toastTimer
        interval: 2600
        repeat: false
        onTriggered: toastVisible = false
    }

    Timer {
        running: spotifyPlaybackActive && token.length > 0
        repeat: true
        interval: 1000
        onTriggered: spotifyProgress = spotifyProgress >= 1 ? 0 : Math.min(1, spotifyProgress + (1 / spotifyDurationSeconds))
    }

    Timer {
        running: token.length > 0
        repeat: true
        interval: 5000
        onTriggered: loadSpotifyStatus()
    }

    WebSocket {
        id: ws
        active: false
        url: app.websocketUrl()
        onTextMessageReceived: function(message) {
            var event = JSON.parse(message)
            if (event.event === "snapshot") {
                mergeRoomsSnapshot(event.payload.rooms || [])
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
        opacity: startupLoaderVisible ? 0 : 1

        Behavior on opacity {
            NumberAnimation {
                duration: 650
                easing.type: Easing.InOutQuad
            }
        }
    }

    Loader {
        anchors.fill: parent
        active: false
        sourceComponent: token ? shellComponent : loginComponent
        opacity: startupLoaderVisible ? 0 : 1

        Behavior on opacity {
            NumberAnimation {
                duration: 650
                easing.type: Easing.InOutQuad
            }
        }
    }

    Loader {
        id: devicesRadarLoader

        property var scannerDevices: allDevices()
        property var scannerRooms: rooms
        property bool scannerRefreshing: devicesRefreshing

        anchors.fill: parent
        anchors.leftMargin: appContentLeftInset
        active: activeView === "Devices"
        visible: active
        source: Qt.resolvedUrl("RadarDemoContent.qml")
        opacity: startupLoaderVisible ? 0 : 1
        z: 5

        Behavior on opacity {
            NumberAnimation {
                duration: 650
                easing.type: Easing.InOutQuad
            }
        }

        onLoaded: {
            item.setRooms(scannerRooms)
            item.refreshing = scannerRefreshing
            item.deviceClicked.connect(function(device) { toggleDevice(device) })
            item.deviceSetRequested.connect(function(device, payload) { setDevice(device, payload) })
            item.refreshRequested.connect(function() { refreshDevicesFromHomeAssistant() })
        }
        onScannerRoomsChanged: {
            if (item)
                item.setRooms(scannerRooms)
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
        anchors.leftMargin: appContentLeftInset
        active: activeView === "Settings"
        visible: active
        sourceComponent: settingsView
        opacity: startupLoaderVisible ? 0 : 1
        z: 5

        Behavior on opacity {
            NumberAnimation {
                duration: 650
                easing.type: Easing.InOutQuad
            }
        }
    }

    BottomToolbar {
        anchors.left: parent.left
        anchors.leftMargin: appNavigatorLeftMargin
        anchors.verticalCenter: parent.verticalCenter
        width: appNavigatorWidth
        height: appNavigatorHeight
        opacity: startupLoaderVisible ? 0 : 1
        z: 10

        Behavior on opacity {
            NumberAnimation {
                duration: 650
                easing.type: Easing.InOutQuad
            }
        }
    }

    SpotifyPlayerWidget {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: 16
        anchors.topMargin: 16
        width: Math.min(320, parent.width - appContentLeftInset - 32)
        height: 190
        visible: token.length > 0 && activeView === "Dashboard" && opacity > 0
        opacity: startupLoaderVisible ? 0 : 1
        z: 9

        Behavior on opacity {
            NumberAnimation {
                duration: 650
                easing.type: Easing.InOutQuad
            }
        }
    }

    CameraFeedPanel {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.leftMargin: appContentLeftInset
        anchors.topMargin: 16
        width: Math.min(320, (parent.width - appContentLeftInset - 32) * 0.5)
        height: Math.min(240, parent.height * 0.5, width * 0.75)
        visible: token.length > 0 && activeView === "Dashboard" && opacity > 0
        opacity: startupLoaderVisible ? 0 : 1
        z: 8

        Behavior on opacity {
            NumberAnimation {
                duration: 650
                easing.type: Easing.InOutQuad
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#212121"
        opacity: startupLoaderVisible ? 1 : 0
        visible: opacity > 0
        z: 100

        Loader {
            anchors.centerIn: parent
            source: Qt.resolvedUrl("components/app_loader.qml")

            onLoaded: {
                item.size = 200
                item.loaderColor = "#4FA593"
                item.trackColor = "#71717a"
                item.duration = 2000
                item.running = Qt.binding(function() { return startupLoaderVisible })
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: 650
                easing.type: Easing.InOutQuad
            }
        }
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: toastVisible ? 18 : -height - 12
        width: Math.min(parent.width - 40, Math.max(220, toastText.implicitWidth + 40))
        height: 42
        radius: 8
        color: "#f1fffc"
        border.color: "#4FA593"
        opacity: toastVisible ? 1 : 0
        z: 120

        Text {
            id: toastText
            anchors.centerIn: parent
            text: toastMessage
            color: "#0f1716"
            font.pixelSize: 13
            font.bold: true
            elide: Text.ElideRight
            width: parent.width - 28
            horizontalAlignment: Text.AlignHCenter
        }

        Behavior on y {
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }

        Behavior on opacity {
            NumberAnimation { duration: 180; easing.type: Easing.OutQuad }
        }
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
            color: "#212121"

            Loader {
                anchors.fill: parent
                sourceComponent: settingsPanel === "" ? settingsHomeView : settingsPlaceholderView
            }
        }
    }

    Component {
        id: settingsHomeView
        Loader {
            anchors.fill: parent
            source: Qt.resolvedUrl("components/CPU_animation_bg.qml")

            onLoaded: {
                item.centerText = "VOKRR"
                item.animateText = true
                item.animateLines = true
                item.animateMarkers = true
                item.showCpuConnections = true
                item.navigationRequested.connect(function(panelName) { openSettingsPanel(panelName) })
                item.restartRequested.connect(function() { restartRaspberryPi() })
            }
        }
    }

    Component {
        id: settingsPlaceholderView
        Rectangle {
            color: "#212121"

            VokrrComponents.Button {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: 18
                variant: "ghost"
                onClicked: settingsPanel = ""

                contentItem: Component {
                    Shape {
                        width: 24
                        height: 24
                        antialiasing: true

                        ShapePath {
                            fillColor: "transparent"
                            strokeColor: "#d7fffb"
                            strokeWidth: 2.6
                            capStyle: ShapePath.RoundCap
                            joinStyle: ShapePath.RoundJoin

                            PathSvg {
                                path: "M15 5 L8 12 L15 19 M9 12 L20 12"
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                width: Math.min(parent.width - 120, 520)
                anchors.top: parent.top
                anchors.topMargin: 76
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 18

                Text {
                    Layout.fillWidth: true
                    text: settingsPanel
                    color: "#ffffff"
                    font.pixelSize: 28
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    visible: settingsPanel === "Network"

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 10

                        Canvas {
                            Layout.preferredWidth: 24
                            Layout.preferredHeight: 24

                            onPaint: {
                                var ctx = getContext("2d")
                                ctx.clearRect(0, 0, width, height)
                                ctx.strokeStyle = "#4FA593"
                                ctx.lineWidth = 2
                                ctx.lineCap = "round"
                                ctx.lineJoin = "round"

                                if (networkStatus && networkStatus.connection_type === "ethernet") {
                                    ctx.strokeRect(6, 7, 12, 10)
                                    ctx.beginPath()
                                    ctx.moveTo(9, 17); ctx.lineTo(9, 20)
                                    ctx.moveTo(15, 17); ctx.lineTo(15, 20)
                                    ctx.moveTo(9, 4); ctx.lineTo(15, 4); ctx.lineTo(15, 7)
                                    ctx.stroke()
                                } else {
                                    ctx.beginPath()
                                    ctx.arc(12, 18, 1.5, 0, Math.PI * 2)
                                    ctx.stroke()
                                    ctx.beginPath()
                                    ctx.arc(12, 18, 6, Math.PI * 1.18, Math.PI * 1.82)
                                    ctx.stroke()
                                    ctx.beginPath()
                                    ctx.arc(12, 18, 11, Math.PI * 1.12, Math.PI * 1.88)
                                    ctx.stroke()
                                }
                            }
                        }

                        Text {
                            text: networkStatus && networkStatus.connection_type === "ethernet"
                                  ? (networkStatus.ethernet || "RJ45")
                                  : (networkStatus && networkStatus.ssid ? networkStatus.ssid : "Not connected")
                            color: "#d7fffb"
                            font.pixelSize: 16
                            font.bold: true
                            elide: Text.ElideRight
                            Layout.maximumWidth: 360
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "Available networks"
                        color: "#7f918d"
                        font.pixelSize: 12
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Repeater {
                        model: networkStatus && networkStatus.configured ? networkStatus.configured : []

                        VokrrComponents.Button {
                            Layout.alignment: Qt.AlignHCenter
                            width: 320
                            height: 50
                            variant: "ghost"
                            onClicked: connectWifi(modelData.key)

                            contentItem: Component {
                                Text {
                                    width: 280
                                    text: modelData.ssid
                                    color: "#d7fffb"
                                    font.pixelSize: 15
                                    font.bold: true
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    visible: settingsPanel === "Profile"

                    SettingsInfoRow {
                        label: "Username"
                        value: currentUser ? currentUser.username : "Kiosk"
                    }
                    SettingsInfoRow {
                        label: "Role"
                        value: currentUser && currentUser.is_admin ? "Admin" : "Local console"
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    visible: settingsPanel === "Information"

                    Repeater {
                        model: [
                            { label: "Project", value: systemInfo.project || "Vokrr" },
                            { label: "Raspberry Pi", value: systemInfo.raspberry_pi_model || "Unknown" },
                            { label: "OS", value: systemInfo.os || "Unknown" },
                            { label: "Kernel", value: systemInfo.kernel || "Unknown" },
                            { label: "Architecture", value: systemInfo.architecture || "Unknown" },
                            { label: "Frontend", value: systemInfo.frontend || "Qt Quick/QML" },
                            { label: "Qt", value: systemInfo.qt || "Unknown" },
                            { label: "Backend", value: systemInfo.backend || "FastAPI" },
                            { label: "Python", value: systemInfo.python || "Unknown" }
                        ]

                        SettingsInfoRow {
                            label: modelData.label
                            value: modelData.value
                        }
                    }
                }
            }
        }
    }

    component SettingsInfoRow: Rectangle {
        property string label: ""
        property string value: ""

        Layout.fillWidth: true
        Layout.preferredHeight: 42
        radius: 8
        color: "#0b1010"
        border.color: "#18302d"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 12

            Text {
                text: label
                color: "#7f918d"
                font.pixelSize: 12
                font.bold: true
                Layout.preferredWidth: 130
                elide: Text.ElideRight
            }

            Text {
                text: value
                color: "#d7fffb"
                font.pixelSize: 13
                Layout.fillWidth: true
                elide: Text.ElideRight
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

    component CameraFeedPanel: VokrrComponents.Card {
        id: cameraPanel

        cornerRadius: 30
        contentPadding: 8
        cardColor: "#212121"

        property var selectedFormat: null
        readonly property real feedRadius: Math.max(0, cornerRadius - contentPadding)

        function bestFormat(device) {
            if (!device || !device.videoFormats || device.videoFormats.length === 0)
                return null

            var best = null
            var bestScore = -1000000
            for (var i = 0; i < device.videoFormats.length; i++) {
                var format = device.videoFormats[i]
                if (!format || !format.resolution)
                    continue

                var width = format.resolution.width
                var height = format.resolution.height
                var fps = format.maxFrameRate || 0
                var pixels = width * height
                var score = -Math.abs(pixels - 307200) / 1000 + fps * 10

                if (width === 640 && height === 480)
                    score += 10000
                if (fps >= 30)
                    score += 500

                if (score > bestScore) {
                    bestScore = score
                    best = format
                }
            }
            return best
        }

        function refreshFormat() {
            selectedFormat = bestFormat(camera.cameraDevice)
        }

        MediaDevices {
            id: mediaDevices
            onVideoInputsChanged: cameraPanel.refreshFormat()
        }

        CaptureSession {
            camera: Camera {
                id: camera
                active: cameraPanel.visible && mediaDevices.videoInputs.length > 0
                cameraDevice: mediaDevices.defaultVideoInput
                cameraFormat: cameraPanel.selectedFormat

                Component.onCompleted: cameraPanel.refreshFormat()
                onCameraDeviceChanged: cameraPanel.refreshFormat()
            }

            videoOutput: videoOutput
        }

        Rectangle {
            id: cameraMask

            anchors.fill: parent
            radius: cameraPanel.feedRadius
            color: "#050809"
            visible: false
            layer.enabled: true
        }

        Item {
            anchors.fill: parent
            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: cameraMask
            }

            VideoOutput {
                anchors.fill: parent
                id: videoOutput
                fillMode: VideoOutput.PreserveAspectCrop
            }

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: 8
                width: 44
                height: 20
                radius: 10
                color: "#d81f35"
                visible: camera.active

                Text {
                    anchors.centerIn: parent
                    text: "LIVE"
                    color: "white"
                    font.pixelSize: 10
                    font.bold: true
                }
            }

            Text {
                anchors.centerIn: parent
                width: parent.width - 28
                visible: mediaDevices.videoInputs.length === 0
                text: "No camera"
                color: "#b8cbc8"
                font.pixelSize: 13
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
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

    component BottomToolbar: VokrrComponents.Card {
        id: rootItem

        readonly property var toolbarItems: [
            { key: "Dashboard", icon: "dashboard" },
            { key: "Devices", icon: "devices" },
            { key: "Settings", icon: "settings" }
        ]
        readonly property int itemCount: toolbarItems.length
        readonly property real gap: 8
        readonly property real itemHeight: (toolbarItemsArea.height - gap * (itemCount - 1)) / itemCount

        cornerRadius: 30
        contentPadding: 8
        cardColor: "#212121"

        function activeIndex() {
            for (var i = 0; i < toolbarItems.length; i++) {
                if (toolbarItems[i].key === activeView)
                    return i
            }
            return 0
        }

        Item {
            id: contentArea

            objectName: "#mainToolbar"
            anchors.fill: parent

            Rectangle {
                id: activeIndicator

                width: parent.width
                height: rootItem.itemHeight
                y: (rootItem.itemHeight + rootItem.gap) * rootItem.activeIndex()
                radius: 24
                color: "#1f09090b"
                border.color: "#16ffffff"
                border.width: 1

                Behavior on y {
                    NumberAnimation {
                        duration: 200
                        easing.type: Easing.InOutQuad
                    }
                }
            }

            Column {
                id: toolbarItemsArea

                anchors.fill: parent
                spacing: rootItem.gap
                clip: true

                Repeater {
                    model: rootItem.toolbarItems

                    ToolbarTab {
                        width: toolbarItemsArea.width
                        height: rootItem.itemHeight
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

    component SpotifyPlayerWidget: VokrrComponents.Card {
        id: spotifyWidget

        cornerRadius: 30
        cardColor: "#212121"

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 64
                spacing: 12

                Rectangle {
                    Layout.preferredWidth: 64
                    Layout.preferredHeight: 64
                    radius: 16
                    clip: true

                    gradient: Gradient {
                        GradientStop { position: 0; color: "#ff9a9e" }
                        GradientStop { position: 1; color: "#fad0c4" }
                    }

                    Image {
                        anchors.fill: parent
                        source: spotifyAlbumArtUrl
                        visible: spotifyAlbumArtUrl.length > 0
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        smooth: true
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        Layout.fillWidth: true
                        text: spotifyTrackTitle
                        color: "#ffffff"
                        font.pixelSize: 21
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        text: spotifyNeedsAuth ? "Tap play to connect" : spotifyArtistName
                        color: "#d1d1d6"
                        font.pixelSize: 14
                        elide: Text.ElideRight
                    }
                }

                RowLayout {
                    Layout.preferredWidth: 38
                    Layout.preferredHeight: 32
                    Layout.alignment: Qt.AlignBottom
                    spacing: 2

                    Repeater {
                        model: 8

                        Rectangle {
                            property real barHeight: 6 + ((index % 4) * 4)

                            Layout.preferredWidth: 3
                            Layout.preferredHeight: barHeight
                            Layout.alignment: Qt.AlignBottom
                            radius: 2

                            gradient: Gradient {
                                orientation: Gradient.Vertical
                                GradientStop { position: 0; color: "#00c6ff" }
                                GradientStop { position: 1; color: "#0072ff" }
                            }

                            SequentialAnimation on barHeight {
                                running: spotifyPlaybackActive
                                loops: Animation.Infinite
                                PauseAnimation { duration: index * 100 }
                                NumberAnimation { to: 26; duration: 400; easing.type: Easing.InOutQuad }
                                NumberAnimation { to: 6; duration: 400; easing.type: Easing.InOutQuad }
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        text: spotifyTimeLabel(spotifyProgress * spotifyDurationSeconds)
                        color: "#8e8e93"
                        font.pixelSize: 12
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: spotifyTimeLabel((1 - spotifyProgress) * spotifyDurationSeconds)
                        color: "#8e8e93"
                        font.pixelSize: 12
                    }
                }

                Rectangle {
                    id: musicProgressTrack

                    Layout.fillWidth: true
                    Layout.preferredHeight: 4
                    radius: 2
                    color: "#1affffff"
                    clip: false

                    Rectangle {
                        width: parent.width * spotifyProgress
                        height: parent.height
                        radius: parent.radius

                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: "#00c6ff" }
                            GradientStop { position: 1; color: "#0072ff" }
                        }
                    }

                    Rectangle {
                        x: Math.max(0, Math.min(parent.width - width, parent.width * spotifyProgress - width / 2))
                        anchors.verticalCenter: parent.verticalCenter
                        width: 10
                        height: 10
                        radius: 5
                        color: "#ffffff"
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 54
                    spacing: 12

                    Item { Layout.fillWidth: true }

                    MusicIconButton {
                        iconName: "previous"
                        onClicked: spotifyAction("previous")
                    }

                    MusicIconButton {
                        iconName: spotifyPlaybackActive ? "pause" : "play"
                        onClicked: spotifyAction("playPause")
                    }

                    MusicIconButton {
                        iconName: "next"
                        onClicked: spotifyAction("next")
                    }

                    Item { Layout.fillWidth: true }

                    MusicIconButton {
                        iconName: "radar"
                        onClicked: spotifyAction("device")
                    }
                }
            }
        }
    }

    component MusicIconButton: Rectangle {
        id: musicButton

        property string iconName: "play"
        property bool highlighted: false
        signal clicked()

        onIconNameChanged: iconCanvas.requestPaint()
        onHighlightedChanged: iconCanvas.requestPaint()

        Layout.preferredWidth: 52
        Layout.preferredHeight: 52
        radius: 26
        color: musicPressArea.pressed ? "#1affffff" : "transparent"
        border.width: 0

        Canvas {
            id: iconCanvas

            anchors.centerIn: parent
            width: musicButton.iconName === "play" || musicButton.iconName === "pause" ? 30 : 22
            height: width
            antialiasing: true
            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                ctx.fillStyle = "#ffffff"
                ctx.strokeStyle = ctx.fillStyle
                ctx.lineWidth = Math.max(2, width * 0.1)
                ctx.lineCap = "round"
                ctx.lineJoin = "round"

                if (musicButton.iconName === "play") {
                    ctx.beginPath()
                    ctx.moveTo(width * 0.3, height * 0.2)
                    ctx.lineTo(width * 0.78, height * 0.5)
                    ctx.lineTo(width * 0.3, height * 0.8)
                    ctx.closePath()
                    ctx.fill()
                } else if (musicButton.iconName === "pause") {
                    ctx.fillRect(width * 0.28, height * 0.22, width * 0.17, height * 0.56)
                    ctx.fillRect(width * 0.56, height * 0.22, width * 0.17, height * 0.56)
                } else if (musicButton.iconName === "previous") {
                    ctx.beginPath()
                    ctx.moveTo(width * 0.92, height * 0.18)
                    ctx.lineTo(width * 0.44, height * 0.5)
                    ctx.lineTo(width * 0.92, height * 0.82)
                    ctx.closePath()
                    ctx.fill()
                    ctx.beginPath()
                    ctx.moveTo(width * 0.5, height * 0.18)
                    ctx.lineTo(width * 0.08, height * 0.5)
                    ctx.lineTo(width * 0.5, height * 0.82)
                    ctx.closePath()
                    ctx.fill()
                    ctx.beginPath()
                    ctx.moveTo(width * 0.05, height * 0.2)
                    ctx.lineTo(width * 0.05, height * 0.8)
                    ctx.stroke()
                } else if (musicButton.iconName === "next") {
                    ctx.beginPath()
                    ctx.moveTo(width * 0.08, height * 0.18)
                    ctx.lineTo(width * 0.56, height * 0.5)
                    ctx.lineTo(width * 0.08, height * 0.82)
                    ctx.closePath()
                    ctx.fill()
                    ctx.beginPath()
                    ctx.moveTo(width * 0.5, height * 0.18)
                    ctx.lineTo(width * 0.92, height * 0.5)
                    ctx.lineTo(width * 0.5, height * 0.82)
                    ctx.closePath()
                    ctx.fill()
                    ctx.beginPath()
                    ctx.moveTo(width * 0.95, height * 0.2)
                    ctx.lineTo(width * 0.95, height * 0.8)
                    ctx.stroke()
                } else {
                    ctx.fillStyle = "transparent"
                    ctx.beginPath()
                    ctx.arc(width * 0.5, height * 0.5, width * 0.42, Math.PI * 1.2, Math.PI * 1.92)
                    ctx.stroke()
                    ctx.beginPath()
                    ctx.arc(width * 0.5, height * 0.5, width * 0.27, Math.PI * 1.2, Math.PI * 1.92)
                    ctx.stroke()
                    ctx.beginPath()
                    ctx.arc(width * 0.5, height * 0.5, width * 0.1, 0, Math.PI * 2)
                    ctx.stroke()
                }
            }
        }

        MouseArea {
            id: musicPressArea
            anchors.fill: parent
            onClicked: musicButton.clicked()
        }
    }

    component GradientBackground: Item {
        Rectangle {
            anchors.fill: parent
            color: "#212121"
        }

        Canvas {
            anchors.fill: parent
            antialiasing: true
            visible: false

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
