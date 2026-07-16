import QtQuick
import QtQuick.Controls
import QtCore
import QtWebSockets

ApplicationWindow {
    id: app

    visible: true
    width: 800
    height: 480
    minimumWidth: 640
    minimumHeight: 360
    title: "Vokrr"
    color: "#030504"

    property string apiBase: vokrrBackendApiBase || "http://localhost:8080"
    property string token: ""
    property string refreshToken: ""
    property var currentUser: null
    property var rooms: []
    property var scenes: []
    property var systemHealth: null
    property var health: null
    property string healthError: ""
    property bool healthLoading: false
    property int healthRangeDays: 1
    property var networkStatus: null
    property var systemInfo: ({})
    property string assistantStatus: "idle"
    property string assistantMessage: "waiting for wake-word"
    property bool realtimeConnected: false
    property bool reconnectPending: false
    property int reconnectDelay: 1000
    property bool loading: false
    property bool refreshInProgress: false
    property var authRetries: []
    property var stateQueues: ({})
    property var mutationVersions: ({})
    property string toastMessage: ""
    property bool toastVisible: false
    property bool startupVisible: true

    readonly property bool backendOnline: systemHealth !== null
    readonly property bool voiceActive: assistantStatus !== "idle"
        && assistantStatus !== "done"
        && assistantStatus !== "error"
        && assistantStatus !== "command_error"

    Settings {
        id: preferences
        category: "interface"
        property bool wakeWordEnabled: true
        property string themeMode: "AUTO"
    }

    function websocketUrl() {
        if (apiBase.indexOf("https://") === 0)
            return "wss://" + apiBase.slice(8) + "/ws?token=" + encodeURIComponent(token)
        if (apiBase.indexOf("http://") === 0)
            return "ws://" + apiBase.slice(7) + "/ws?token=" + encodeURIComponent(token)
        return "ws://localhost:8080/ws?token=" + encodeURIComponent(token)
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
            } catch (error) {
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

    function refreshSession(callback) {
        if (!refreshToken) {
            callback(false)
            return
        }
        authRetries.push(callback)
        if (refreshInProgress)
            return
        refreshInProgress = true
        http("POST", "/api/auth/refresh", { refresh_token: refreshToken }, function(status, data) {
            refreshInProgress = false
            var success = status >= 200 && status < 300 && data && data.access_token
            if (success) {
                token = data.access_token
                refreshToken = data.refresh_token || ""
                currentUser = data.user || currentUser
                realtime.active = false
                realtime.active = true
            } else {
                clearSession()
            }
            var callbacks = authRetries.slice()
            authRetries = []
            for (var i = 0; i < callbacks.length; i++)
                callbacks[i](success)
        }, false, true)
    }

    function kioskLogin() {
        if (loading || token)
            return
        loading = true
        http("POST", "/api/auth/kiosk", null, function(status, data) {
            loading = false
            if (status >= 200 && status < 300 && data && data.access_token)
                applySession(data)
        }, false)
    }

    function applySession(data) {
        token = data.access_token || ""
        refreshToken = data.refresh_token || ""
        currentUser = data.user || null
        loadSnapshot()
        loadSystemHealth()
        loadUltrahuman(false)
        loadNetworkStatus()
        loadSystemInfo()
        realtime.active = true
    }

    function clearSession() {
        realtime.active = false
        token = ""
        refreshToken = ""
        currentUser = null
        realtimeConnected = false
    }

    function isVisibleDevice(device) {
        if (!device || !device.state || !device.capabilities)
            return false
        var state = device.state.state
        if (state === "unknown" || state === "unavailable" || state === "offline" || state === "unreachable")
            return false
        return device.capabilities.indexOf("toggle") !== -1
            || device.capabilities.indexOf("brightness") !== -1
            || device.capabilities.indexOf("percentage") !== -1
            || device.capabilities.indexOf("color_temperature") !== -1
            || device.capabilities.indexOf("color") !== -1
    }

    function mergeRoomsSnapshot(snapshot) {
        var incoming = snapshot || []
        var filtered = []
        for (var i = 0; i < incoming.length; i++) {
            var room = JSON.parse(JSON.stringify(incoming[i]))
            var devices = room.devices || []
            var visible = []
            for (var j = 0; j < devices.length; j++) {
                if (isVisibleDevice(devices[j]))
                    visible.push(devices[j])
            }
            room.devices = visible
            filtered.push(room)
        }
        rooms = filtered
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

    function findDevice(deviceId) {
        var devices = allDevices()
        for (var i = 0; i < devices.length; i++) {
            if (devices[i].id === deviceId)
                return devices[i]
        }
        return null
    }

    function mergeDevice(updated) {
        if (!updated)
            return
        var next = JSON.parse(JSON.stringify(rooms))
        for (var i = 0; i < next.length; i++) {
            var devices = next[i].devices || []
            for (var j = 0; j < devices.length; j++) {
                if (devices[j].id === updated.id || (updated.entity_id && devices[j].entity_id === updated.entity_id)) {
                    if (isVisibleDevice(updated))
                        devices[j] = updated
                    else
                        devices.splice(j, 1)
                    rooms = next
                    return
                }
            }
        }
    }

    function replaceRoom(updatedRoom) {
        if (!updatedRoom)
            return
        var next = JSON.parse(JSON.stringify(rooms))
        for (var i = 0; i < next.length; i++) {
            if (next[i].id === updatedRoom.id) {
                next[i] = updatedRoom
                rooms = next
                return
            }
        }
    }

    function patchDevice(device, payload) {
        var updated = JSON.parse(JSON.stringify(device))
        updated.state = updated.state || {}
        if (payload.state !== undefined) {
            updated.state.is_on = payload.state
            updated.state.state = payload.state ? "on" : "off"
        }
        if (payload.brightness !== undefined) {
            updated.state.brightness = payload.brightness
            updated.state.is_on = payload.brightness > 0
            updated.state.state = payload.brightness > 0 ? "on" : "off"
        }
        if (payload.percentage !== undefined) {
            updated.state.percentage = payload.percentage
            updated.state.is_on = payload.percentage > 0
            updated.state.state = payload.percentage > 0 ? "on" : "off"
        }
        if (payload.rgb_color !== undefined) {
            updated.state.rgb_color = payload.rgb_color
            updated.state.is_on = true
            updated.state.state = "on"
        }
        if (payload.color_temp_kelvin !== undefined) {
            updated.state.color_temp_kelvin = payload.color_temp_kelvin
            updated.state.is_on = true
            updated.state.state = "on"
        }
        return updated
    }

    function nextMutation(deviceId) {
        var next = Object.assign({}, mutationVersions)
        next[deviceId] = (next[deviceId] || 0) + 1
        mutationVersions = next
        return next[deviceId]
    }

    function setDevice(device, payload) {
        if (!device || !payload)
            return
        var original = JSON.parse(JSON.stringify(device))
        var version = nextMutation(device.id)
        mergeDevice(patchDevice(device, payload))
        http("POST", "/api/devices/" + encodeURIComponent(device.id) + "/set", payload, function(status, data) {
            if (mutationVersions[device.id] !== version)
                return
            if (status >= 200 && status < 300 && data) {
                // Keep the requested visual state until the HA WebSocket confirms it.
                mergeDevice(patchDevice(data, payload))
            } else {
                mergeDevice(original)
                loadSnapshot()
                showToast("Could not update " + device.name)
            }
        })
    }

    function toggleDevice(device) {
        if (!device || !device.state)
            return
        var desired = !device.state.is_on
        var queue = stateQueues[device.id]
        if (!queue) {
            queue = {
                busy: false,
                desired: desired,
                original: JSON.parse(JSON.stringify(device))
            }
            stateQueues[device.id] = queue
        } else {
            queue.desired = desired
        }
        mergeDevice(patchDevice(device, { state: desired }))
        if (!queue.busy)
            dispatchQueuedState(device.id)
    }

    function dispatchQueuedState(deviceId) {
        var queue = stateQueues[deviceId]
        var device = findDevice(deviceId)
        if (!queue || !device)
            return
        var sentState = queue.desired
        queue.busy = true
        http("POST", "/api/devices/" + encodeURIComponent(deviceId) + "/set", { state: sentState }, function(status, data) {
            var currentQueue = stateQueues[deviceId]
            if (!currentQueue)
                return
            if (currentQueue.desired !== sentState) {
                currentQueue.busy = false
                dispatchQueuedState(deviceId)
                return
            }
            delete stateQueues[deviceId]
            if (status >= 200 && status < 300 && data) {
                mergeDevice(data)
            } else {
                mergeDevice(currentQueue.original)
                loadSnapshot()
                showToast("Device did not confirm the change")
            }
        })
    }

    function setRoomState(room, state) {
        if (!room)
            return
        var before = JSON.parse(JSON.stringify(rooms))
        var optimistic = JSON.parse(JSON.stringify(room))
        var devices = optimistic.devices || []
        for (var i = 0; i < devices.length; i++) {
            devices[i].state.is_on = state
            devices[i].state.state = state ? "on" : "off"
        }
        replaceRoom(optimistic)
        http("POST", "/api/rooms/" + encodeURIComponent(room.id) + "/set", { state: state }, function(status, data) {
            if (status >= 200 && status < 300 && data)
                replaceRoom(data)
            else {
                rooms = before
                loadSnapshot()
                showToast("Could not update " + room.name)
            }
        })
    }

    function loadSnapshot() {
        if (!token)
            return
        http("GET", "/api/rooms", null, function(status, data) {
            if (status >= 200 && status < 300 && data)
                mergeRoomsSnapshot(data)
        })
        http("GET", "/api/scenes", null, function(status, data) {
            if (status >= 200 && status < 300 && data)
                scenes = data
        })
    }

    function loadSystemHealth() {
        http("GET", "/api/system/health", null, function(status, data) {
            if (status >= 200 && status < 300 && data) {
                systemHealth = data
            } else {
                systemHealth = null
            }
        }, false)
    }

    function loadUltrahuman(force) {
        if (!token || healthLoading)
            return
        healthLoading = true
        var method = force ? "POST" : "GET"
        var path = force ? "/api/health/refresh" : "/api/health/dashboard"
        path += "?days=" + healthRangeDays
        http(method, path, null, function(status, data) {
            healthLoading = false
            if (status >= 200 && status < 300 && data) {
                health = data
                healthError = data.sync && data.sync.message ? String(data.sync.message) : ""
                if (force)
                    showToast(data.sync && data.sync.connected ? "Health data refreshed" : "Health refresh unavailable")
            } else {
                healthError = "Health sync unavailable"
                if (force)
                    showToast(healthError)
            }
        })
    }

    function loadNetworkStatus() {
        if (!token)
            return
        http("GET", "/api/system/network", null, function(status, data) {
            if (status >= 200 && status < 300 && data)
                networkStatus = data
        })
    }

    function loadSystemInfo() {
        if (!token)
            return
        http("GET", "/api/system/info", null, function(status, data) {
            if (status >= 200 && status < 300 && data)
                systemInfo = data
        })
    }

    function showToast(message) {
        toastMessage = message
        toastVisible = true
        toastTimer.restart()
    }

    function handleRealtimeStatus(status) {
        realtimeConnected = status === WebSocket.Open
        if (status === WebSocket.Open) {
            reconnectPending = false
            reconnectDelay = 1000
            loadSnapshot()
        } else if (token && (status === WebSocket.Error || status === WebSocket.Closed) && !reconnectPending) {
            reconnectPending = true
            reconnectTimer.interval = reconnectDelay
            reconnectTimer.restart()
            reconnectDelay = Math.min(reconnectDelay * 2, 15000)
        }
    }

    Component.onCompleted: {
        loadSystemHealth()
        kioskLogin()
    }

    Timer {
        interval: 850
        running: true
        repeat: false
        onTriggered: startupVisible = false
    }

    Timer {
        interval: 5000
        running: !token
        repeat: true
        onTriggered: {
            loadSystemHealth()
            kioskLogin()
        }
    }

    Timer {
        interval: 7000
        running: token.length > 0
        repeat: true
        onTriggered: {
            loadSystemHealth()
            loadNetworkStatus()
            if (!realtimeConnected)
                loadSnapshot()
        }
    }

    Timer {
        interval: 60000
        running: app.token.length > 0 && shell.currentScreen === "health"
        repeat: true
        onTriggered: app.loadUltrahuman(false)
    }

    Timer {
        id: reconnectTimer
        repeat: false
        onTriggered: {
            reconnectPending = false
            if (token) {
                realtime.active = false
                realtime.active = true
            }
        }
    }

    Timer {
        id: toastTimer
        interval: 2500
        repeat: false
        onTriggered: toastVisible = false
    }

    WebSocket {
        id: realtime
        active: false
        url: app.websocketUrl()
        onStatusChanged: function(status) { app.handleRealtimeStatus(status) }
        onTextMessageReceived: function(message) {
            var event
            try {
                event = JSON.parse(message)
            } catch (error) {
                return
            }
            if (event.event === "snapshot") {
                mergeRoomsSnapshot(event.payload.rooms || [])
            } else if (event.event === "device.updated") {
                mergeDevice(event.payload)
            } else if (event.event === "voice.command") {
                assistantMessage = event.payload.message || "Command complete"
                assistantStatus = event.payload.understood ? "done" : "error"
                shell.navigate("jarvis")
            } else if (event.event === "voice.status") {
                assistantMessage = event.payload.message || "waiting for wake-word"
                assistantStatus = event.payload.status || "idle"
                if (voiceActive)
                    shell.navigate("jarvis")
            }
        }
    }

    VokrrGtShell {
        id: shell
        anchors.fill: parent
        rooms: app.rooms
        scenes: app.scenes
        health: app.health
        healthError: app.healthError
        healthLoading: app.healthLoading
        healthRangeDays: app.healthRangeDays
        backendOnline: app.backendOnline
        authenticated: app.token.length > 0
        realtimeConnected: app.realtimeConnected
        userName: app.currentUser && app.currentUser.username ? app.currentUser.username : "Dushyant"
        apiBase: app.apiBase
        systemInfo: app.systemInfo
        assistantStatus: app.assistantStatus
        assistantMessage: app.assistantMessage
        voicePipelineActive: app.voiceActive
        wakeWordEnabled: preferences.wakeWordEnabled
        themeMode: preferences.themeMode
        reducedMotion: vokrrReducedMotion
        opacity: startupVisible ? 0 : 1

        Behavior on opacity {
            NumberAnimation { duration: vokrrReducedMotion ? 0 : 220; easing.type: Easing.OutCubic }
        }

        onDeviceToggleRequested: function(device) { app.toggleDevice(device) }
        onDeviceSetRequested: function(device, payload) { app.setDevice(device, payload) }
        onRoomSetRequested: function(room, state) { app.setRoomState(room, state) }
        onHealthRangeRequested: function(days) {
            app.healthRangeDays = days
            app.loadUltrahuman(false)
        }
        onHealthRefreshRequested: app.loadUltrahuman(true)
        onCurrentScreenChanged: {
            if (currentScreen === "health")
                app.loadUltrahuman(false)
        }
        onWakeWordRequested: function(enabled) { preferences.wakeWordEnabled = enabled }
        onThemeModeRequested: function(mode) { preferences.themeMode = mode }
        onSettingsActivated: {
            app.loadSystemInfo()
            app.loadNetworkStatus()
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#060807"
        opacity: startupVisible ? 1 : 0
        visible: opacity > 0
        z: 100

        Item {
            anchors.centerIn: parent
            width: 100
            height: 100

            Rectangle {
                anchors.centerIn: parent
                width: 68
                height: 68
                radius: 34
                color: "transparent"
                border.width: 1
                border.color: "#55d9cba8"
            }

            Rectangle {
                anchors.centerIn: parent
                width: 48
                height: 48
                radius: 24
                color: "transparent"
                border.width: 3
                border.color: "#2ec79a"
                RotationAnimation on rotation {
                    running: !vokrrReducedMotion
                    from: 0
                    to: 360
                    duration: 1300
                    loops: Animation.Infinite
                }
            }

            Rectangle {
                anchors.centerIn: parent
                width: 18
                height: 18
                radius: 9
                color: "#2ec79a"
            }
        }

        Behavior on opacity {
            NumberAnimation { duration: vokrrReducedMotion ? 0 : 220; easing.type: Easing.OutCubic }
        }
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: toastVisible ? 14 : -52
        width: Math.min(parent.width - 32, Math.max(240, toastLabel.implicitWidth + 42))
        height: 40
        radius: 8
        color: "#e9f7f2"
        border.color: "#2ec79a"
        opacity: toastVisible ? 1 : 0
        z: 120

        Text {
            id: toastLabel
            anchors.centerIn: parent
            width: parent.width - 28
            text: toastMessage
            color: "#0c1713"
            font.family: "Jost"
            font.pixelSize: 13
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }

        Behavior on y {
            NumberAnimation { duration: vokrrReducedMotion ? 0 : 180; easing.type: Easing.OutCubic }
        }
        Behavior on opacity {
            NumberAnimation { duration: vokrrReducedMotion ? 0 : 140; easing.type: Easing.OutCubic }
        }
    }
}
