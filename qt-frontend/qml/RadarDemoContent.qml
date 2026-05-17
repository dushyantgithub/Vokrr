import QtQuick
import QtQuick.Shapes
import "components"

Item {
    id: root

    property var devices: []
    property var sourceDevices: []
    property var rooms: []
    property var roomItems: []
    property var deviceStates: ({})
    property var devicePayloads: ({})
    property bool refreshing: false
    property bool darkMode: true
    property int navInset: 0
    property string selectedRoomId: ""
    readonly property color themeTextColor: darkMode ? "#e8e8e8" : "#212121"
    readonly property color themeMutedColor: darkMode ? "#71717a" : "#64748b"
    readonly property color themeLineColor: darkMode ? "#334155" : "#cbd5e1"
    signal deviceClicked(var device)
    signal deviceSetRequested(var device, var payload)
    signal refreshRequested()

    function deviceKey(device) {
        if (!device)
            return ""
        if (device.is_room)
            return device.id || ("room:" + device.room_id)
        if (device.is_switchboard)
            return device.id
        return device.id || (device.room_name + ":" + device.name)
    }

    function isSwitchboard(item) {
        return !!(item && item.is_switchboard)
    }

    function uniqueDeviceList(sourceDevices) {
        var seen = {}
        var result = []
        for (var i = 0; i < sourceDevices.length; i++) {
            var device = sourceDevices[i]
            if (!device)
                continue
            var key = deviceKey(device)
            if (!key || seen[key])
                continue
            seen[key] = true
            result.push(device)
        }
        return result
    }

    function displayDeviceList(sourceDevices) {
        var unique = uniqueDeviceList(sourceDevices || [])
        var groups = {}
        var order = []
        var result = []

        for (var i = 0; i < unique.length; i++) {
            var device = unique[i]
            if (!device || device.type !== "switch" || !device.ha_device_id) {
                result.push(device)
                continue
            }

            var groupKey = "switchboard:" + device.ha_device_id
            if (!groups[groupKey]) {
                groups[groupKey] = {
                    id: groupKey,
                    is_switchboard: true,
                    ha_device_id: device.ha_device_id,
                    name: "Switch Board",
                    room_name: device.room_name,
                    device_keys: [],
                    devices: []
                }
                order.push(groupKey)
            }
            groups[groupKey].device_keys.push(deviceKey(device))
            groups[groupKey].devices.push(device)
        }

        for (var j = 0; j < order.length; j++) {
            var group = groups[order[j]]
            if (group.devices.length > 1)
                result.push(group)
            else
                result.push(group.devices[0])
        }

        return result
    }

    function sameDeviceList(left, right) {
        if (left.length !== right.length)
            return false
        for (var i = 0; i < left.length; i++) {
            if (deviceKey(left[i]) !== deviceKey(right[i]))
                return false
        }
        return true
    }

    function roomKey(room) {
        if (!room)
            return ""
        return room.id || room.name || ""
    }

    function makeRoomItems(nextRooms) {
        var result = []
        for (var i = 0; i < nextRooms.length; i++) {
            var room = nextRooms[i]
            var key = roomKey(room)
            if (!key)
                continue
            result.push({
                id: "room:" + key,
                is_room: true,
                room_id: key,
                name: room.name || "Room",
                devices: room.devices || [],
                device_count: (room.devices || []).length
            })
        }
        return result
    }

    function flattenRooms(nextRooms) {
        var result = []
        for (var i = 0; i < nextRooms.length; i++) {
            var room = nextRooms[i]
            var devicesInRoom = room.devices || []
            for (var j = 0; j < devicesInRoom.length; j++)
                result.push(devicesInRoom[j])
        }
        return result
    }

    function selectedRoom() {
        if (!selectedRoomId)
            return null
        for (var i = 0; i < rooms.length; i++) {
            if (roomKey(rooms[i]) === selectedRoomId)
                return rooms[i]
        }
        return null
    }

    function roomDevices(roomId) {
        var room = selectedRoom()
        if (room && room.devices)
            return room.devices

        var result = []
        for (var i = 0; i < sourceDevices.length; i++) {
            var device = sourceDevices[i]
            if (device && device.room_id === roomId)
                result.push(device)
        }
        return result
    }

    function refreshDeviceDisplay() {
        if (!selectedRoomId) {
            if (devices.length)
                devices = []
            return
        }

        var displayDevices = displayDeviceList(roomDevices(selectedRoomId))
        if (!sameDeviceList(devices, displayDevices))
            devices = displayDevices
    }

    function setRooms(nextRooms) {
        var incomingRooms = nextRooms || []
        rooms = incomingRooms
        roomItems = makeRoomItems(incomingRooms)

        if (selectedRoomId && !selectedRoom())
            selectedRoomId = ""

        setDevices(flattenRooms(incomingRooms))
    }

    function setDevices(nextDevices) {
        var unique = uniqueDeviceList(nextDevices || [])
        sourceDevices = unique

        var nextPayloads = {}
        for (var i = 0; i < unique.length; i++)
        {
            updateDevice(unique[i])
            nextPayloads[deviceKey(unique[i])] = unique[i]
        }
        devicePayloads = nextPayloads

        refreshDeviceDisplay()
    }

    function selectRoom(room) {
        if (!room || !room.room_id)
            return
        selectedRoomId = room.room_id
        refreshDeviceDisplay()
    }

    function backToRooms() {
        selectedRoomId = ""
        refreshDeviceDisplay()
    }

    function currentDevice(device) {
        var key = deviceKey(device)
        if (key && devicePayloads.hasOwnProperty(key))
            return devicePayloads[key]
        return device
    }

    function currentSwitchboardDevices(board) {
        var keys = board && board.device_keys ? board.device_keys : []
        var result = []
        for (var i = 0; i < keys.length; i++) {
            if (devicePayloads.hasOwnProperty(keys[i]))
                result.push(devicePayloads[keys[i]])
        }
        return result.length ? result : ((board && board.devices) || [])
    }

    function updateDevice(device) {
        var key = deviceKey(device)
        if (!key || !device || !device.state)
            return

        var nextStates = {}
        for (var existingKey in deviceStates)
            nextStates[existingKey] = deviceStates[existingKey]
        nextStates[key] = !!device.state.is_on
        deviceStates = nextStates
    }

    function deviceIsOn(device) {
        var key = deviceKey(device)
        if (key && deviceStates.hasOwnProperty(key))
            return deviceStates[key]
        return !!(device && device.state && device.state.is_on)
    }

    function deviceLabel(device) {
        if (!device)
            return ""
        if (device.is_room)
            return device.name || "Room"
        if (device.is_switchboard)
            return device.name || device.room_name || "Switches"
        return device.name || device.id || "Device"
    }

    function roomIconKind(room) {
        var name = room && room.name ? room.name.toLowerCase() : ""
        if (name.indexOf("bedroom") !== -1)
            return "bedroom"
        if (name.indexOf("living") !== -1)
            return "living"
        if (name.indexOf("kitchen") !== -1)
            return "kitchen"
        if (name.indexOf("gaming") !== -1)
            return "gaming"
        return ""
    }

    function itemWidth(item) {
        if (item && item.is_room)
            return 118
        if (isSwitchboard(item))
            return Math.max(132, ((item.devices || []).length * 46) + 22)
        if (item && item.type === "fan")
            return 180
        return 132
    }

    function itemHeight(item) {
        if (item && item.type === "fan")
            return 190
        return 122
    }

    function scatterX(index, areaWidth, visualWidth) {
        var positions = [0.10, 0.43, 0.76, 0.24, 0.61, 0.08, 0.44, 0.78, 0.27, 0.58, 0.14, 0.72]
        var base = positions[index % positions.length]
        var cycle = Math.floor(index / positions.length)
        var jitter = (((index * 37 + cycle * 19) % 25) - 12) / Math.max(1, areaWidth)
        return Math.max(10, Math.min(areaWidth - visualWidth - 10, (base + jitter) * areaWidth))
    }

    function scatterY(index, areaHeight, visualHeight) {
        var positions = [0.08, 0.18, 0.10, 0.36, 0.42, 0.62, 0.68, 0.58, 0.82, 0.78, 0.28, 0.88]
        var base = positions[index % positions.length]
        var cycle = Math.floor(index / positions.length)
        var jitter = (((index * 29 + cycle * 17) % 21) - 10) / Math.max(1, areaHeight)
        return Math.max(8, Math.min(areaHeight - visualHeight, (base + jitter) * areaHeight))
    }

    Rectangle {
        anchors.fill: parent
        color: root.darkMode ? "#212121" : "#e8e8e8"
    }

    Item {
        id: container

        width: Math.min(parent.width, 760)
        height: Math.min(parent.height, 384)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        clip: true

        Radar {
            width: 420
            height: 420
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: -250
            z: 10
        }

        Rectangle {
            height: 1
            width: parent.width
            anchors.bottom: parent.bottom
            color: root.themeLineColor
            opacity: 0.8
            z: 41
        }
    }

    Item {
        id: scatterLayer

        anchors.fill: parent
        anchors.margins: 18
        anchors.bottomMargin: 88
        z: 50

        Repeater {
            model: root.selectedRoomId ? root.devices : root.roomItems

            Item {
                width: root.itemWidth(modelData)
                height: root.itemHeight(modelData)
                x: root.scatterX(index, scatterLayer.width, width)
                y: root.scatterY(index, scatterLayer.height, height)
                clip: true

                Item {
                    visible: !!(modelData && modelData.is_room)
                    width: 118
                    height: 108
                    anchors.centerIn: parent

                    Button {
                        id: roomButton

                        variant: "shadow"
                        darkMode: root.darkMode
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        onClicked: root.selectRoom(modelData)

                        contentItem: Component {
                            Item {
                                width: 24
                                height: 24

                                readonly property string iconKind: root.roomIconKind(modelData)

                                Text {
                                    anchors.centerIn: parent
                                    visible: parent.iconKind.length === 0
                                    text: modelData && modelData.name ? modelData.name.charAt(0).toUpperCase() : "R"
                                    color: root.themeTextColor
                                    font.pixelSize: 18
                                    font.bold: true
                                }

                                Shape {
                                    anchors.fill: parent
                                    visible: parent.iconKind === "bedroom"
                                    antialiasing: true

                                    ShapePath {
                                        fillColor: "transparent"
                                        strokeColor: root.themeTextColor
                                        strokeWidth: 2
                                        capStyle: ShapePath.RoundCap
                                        joinStyle: ShapePath.RoundJoin

                                        PathSvg {
                                            path: "M22 19V16M12 16V8H18C20.2091 8 22 9.79086 22 12V16M12 16H2M12 16H22M2 6V16M2 19V16M9.00001 11C9.00001 12.1046 8.10458 13 7.00001 13C5.89544 13 5.00001 12.1046 5.00001 11C5.00001 9.89543 5.89544 9 7.00001 9C8.10458 9 9.00001 9.89543 9.00001 11Z"
                                        }
                                    }
                                }

                                Shape {
                                    anchors.fill: parent
                                    visible: parent.iconKind === "living"
                                    antialiasing: true

                                    ShapePath {
                                        fillColor: "transparent"
                                        strokeColor: root.themeTextColor
                                        strokeWidth: 2
                                        joinStyle: ShapePath.RoundJoin

                                        PathSvg { path: "M6 10.5H2V17.5H6V10.5Z" }
                                    }

                                    ShapePath {
                                        fillColor: "transparent"
                                        strokeColor: root.themeTextColor
                                        strokeWidth: 2
                                        joinStyle: ShapePath.RoundJoin

                                        PathSvg { path: "M22 10.5H18V17.5H22V10.5Z" }
                                    }

                                    ShapePath {
                                        fillColor: "transparent"
                                        strokeColor: root.themeTextColor
                                        strokeWidth: 2
                                        capStyle: ShapePath.RoundCap
                                        joinStyle: ShapePath.RoundJoin

                                        PathSvg { path: "M18 13.5H6V17.5H18V13.5Z" }
                                    }

                                    ShapePath {
                                        fillColor: "transparent"
                                        strokeColor: root.themeTextColor
                                        strokeWidth: 2
                                        capStyle: ShapePath.RoundCap
                                        joinStyle: ShapePath.RoundJoin

                                        PathSvg { path: "M4 10V4H20V10M4 18V20M20 18V20" }
                                    }
                                }

                                Shape {
                                    anchors.fill: parent
                                    visible: parent.iconKind === "kitchen"
                                    antialiasing: true

                                    ShapePath {
                                        fillColor: "transparent"
                                        strokeColor: root.themeTextColor
                                        strokeWidth: 2
                                        capStyle: ShapePath.RoundCap
                                        joinStyle: ShapePath.RoundJoin

                                        PathSvg {
                                            path: "M5 4V7C5 7.79565 5.31607 8.55871 5.87868 9.12132C6.44129 9.68393 7.20435 10 8 10C8.79565 10 9.55871 9.68393 10.1213 9.12132C10.6839 8.55871 11 7.79565 11 7V4M19 3V15H14C13.977 11.319 14.184 7.594 19 3ZM19 15V21H18V18L19 15ZM8 4V21V4Z"
                                        }
                                    }
                                }

                                Shape {
                                    anchors.fill: parent
                                    visible: parent.iconKind === "gaming"
                                    antialiasing: true

                                    ShapePath {
                                        fillColor: root.themeTextColor
                                        strokeColor: "transparent"

                                        PathSvg {
                                            path: "M17.25 9.04053C17.25 9.23944 17.171 9.4302 17.0303 9.57086C16.8897 9.71151 16.6989 9.79053 16.5 9.79053C16.3011 9.79053 16.1103 9.71151 15.9697 9.57086C15.829 9.4302 15.75 9.23944 15.75 9.04053C15.75 8.84161 15.829 8.65085 15.9697 8.5102C16.1103 8.36955 16.3011 8.29053 16.5 8.29053C16.6989 8.29053 16.8897 8.36955 17.0303 8.5102C17.171 8.65085 17.25 8.84161 17.25 9.04053V9.04053ZM15 11.2905C15.1989 11.2905 15.3897 11.2115 15.5303 11.0709C15.671 10.9302 15.75 10.7394 15.75 10.5405C15.75 10.3416 15.671 10.1508 15.5303 10.0102C15.3897 9.86954 15.1989 9.79053 15 9.79053C14.8011 9.79053 14.6103 9.86954 14.4697 10.0102C14.329 10.1508 14.25 10.3416 14.25 10.5405C14.25 10.7394 14.329 10.9302 14.4697 11.0709C14.6103 11.2115 14.8011 11.2905 15 11.2905ZM18.75 10.5405C18.75 10.7394 18.671 10.9302 18.5303 11.0709C18.3897 11.2115 18.1989 11.2905 18 11.2905C17.8011 11.2905 17.6103 11.2115 17.4697 11.0709C17.329 10.9302 17.25 10.7394 17.25 10.5405C17.25 10.3416 17.329 10.1508 17.4697 10.0102C17.6103 9.86954 17.8011 9.79053 18 9.79053C18.1989 9.79053 18.3897 9.86954 18.5303 10.0102C18.671 10.1508 18.75 10.3416 18.75 10.5405V10.5405ZM16.5 12.7905C16.6989 12.7905 16.8897 12.7115 17.0303 12.5709C17.171 12.4302 17.25 12.2394 17.25 12.0405C17.25 11.8416 17.171 11.6508 17.0303 11.5102C16.8897 11.3695 16.6989 11.2905 16.5 11.2905C16.3011 11.2905 16.1103 11.3695 15.9697 11.5102C15.829 11.6508 15.75 11.8416 15.75 12.0405C15.75 12.2394 15.829 12.4302 15.9697 12.5709C16.1103 12.7115 16.3011 12.7905 16.5 12.7905ZM6.75 8.29053H8.25V9.79053H9.75V11.2905H8.25V12.7905H6.75V11.2905H5.25V9.79053H6.75V8.29053Z"
                                        }
                                    }

                                    ShapePath {
                                        fillColor: root.themeTextColor
                                        strokeColor: "transparent"

                                        PathSvg {
                                            path: "M4.5764 4.89003C4.55078 4.79479 4.54419 4.69542 4.55702 4.59763C4.56985 4.49984 4.60185 4.40554 4.65117 4.32014C4.70049 4.23473 4.76618 4.15988 4.84446 4.09989C4.92275 4.0399 5.0121 3.99594 5.1074 3.97053L8.0054 3.19353C8.10502 3.16698 8.20906 3.16126 8.31099 3.17672C8.41293 3.19218 8.51059 3.22849 8.59786 3.28339C8.68514 3.33829 8.76015 3.41059 8.81823 3.49578C8.8763 3.58098 8.91619 3.67723 8.9354 3.77853C9.9179 3.66003 10.9604 3.60303 11.9999 3.60303C13.0799 3.60303 14.1644 3.66453 15.1799 3.79203C15.1974 3.68919 15.2362 3.59115 15.2938 3.50415C15.3514 3.41716 15.4265 3.34314 15.5143 3.28681C15.6021 3.23049 15.7007 3.1931 15.8037 3.17703C15.9068 3.16097 16.0121 3.16659 16.1129 3.19353L19.0109 3.97053C19.1215 4.00013 19.2238 4.05465 19.3101 4.12991C19.3963 4.20518 19.4642 4.29919 19.5085 4.40474C19.5528 4.51029 19.5724 4.62458 19.5657 4.73886C19.559 4.85314 19.5262 4.96437 19.4699 5.06403C19.6799 5.19903 19.8689 5.34903 20.0294 5.50953C20.6414 6.12153 21.1994 7.08453 21.6719 8.16753C22.1519 9.26703 22.5704 10.554 22.8794 11.8665C23.1884 13.179 23.3894 14.5365 23.4254 15.7755C23.4614 16.9995 23.3369 18.1785 22.9334 19.0905C22.7494 19.5 22.4407 19.8408 22.0515 20.0644C21.6622 20.288 21.2123 20.3829 20.7659 20.3355C19.8119 20.235 19.0934 19.7445 18.4964 19.176C18.1289 18.828 17.7524 18.387 17.3879 17.964C17.1989 17.742 17.0129 17.526 16.8359 17.3295C15.7439 16.1235 14.4404 15.039 11.9999 15.039C9.5594 15.039 8.2559 16.1235 7.1639 17.3295C6.9854 17.526 6.8009 17.742 6.6119 17.964C6.2474 18.387 5.8709 18.8265 5.5034 19.176C4.9064 19.746 4.1879 20.235 3.2339 20.3355C2.78751 20.3829 2.33757 20.288 1.94832 20.0644C1.55907 19.8408 1.2504 19.5 1.0664 19.0905C0.661397 18.1785 0.538397 16.998 0.572897 15.7755C0.608897 14.5365 0.812897 13.1805 1.1204 11.8665C1.4294 10.554 1.8494 9.26703 2.3279 8.16753C2.8004 7.08453 3.3584 6.12153 3.9689 5.50953C4.16499 5.31719 4.38298 5.14854 4.6184 5.00703C4.60113 4.96876 4.58708 4.92913 4.5764 4.88853V4.89003ZM7.6304 5.50803C6.3149 5.78553 5.4269 6.17253 5.0309 6.57003C4.6169 6.98403 4.1504 7.74453 3.7034 8.76753C3.22919 9.87991 2.85374 11.0319 2.5814 12.21C2.29369 13.3934 2.12337 14.6022 2.0729 15.819C2.0399 16.9515 2.1659 17.871 2.4374 18.483C2.493 18.6022 2.58451 18.701 2.69911 18.7656C2.81371 18.8302 2.94564 18.8572 3.0764 18.843C3.5669 18.792 3.9914 18.5445 4.4699 18.09C4.7879 17.787 5.0699 17.4555 5.3924 17.079C5.5919 16.845 5.8064 16.5945 6.0524 16.323C7.2914 14.9535 8.9669 13.5405 11.9999 13.5405C15.0329 13.5405 16.7084 14.9535 17.9474 16.323C18.1934 16.5945 18.4079 16.845 18.6074 17.079C18.9284 17.4555 19.2119 17.787 19.5299 18.09C20.0069 18.5445 20.4314 18.792 20.9234 18.8445C21.0543 18.8586 21.1864 18.8313 21.301 18.7665C21.4156 18.7016 21.507 18.6025 21.5624 18.483C21.8324 17.871 21.9599 16.953 21.9269 15.819C21.8764 14.6022 21.7061 13.3934 21.4184 12.21C21.146 11.0319 20.7706 9.87993 20.2964 8.76753C19.8494 7.74453 19.3814 6.98253 18.9689 6.57003C18.5729 6.17253 17.6849 5.78553 16.3694 5.50803C15.0944 5.23953 13.5539 5.10303 11.9999 5.10303C10.4459 5.10303 8.9054 5.23953 7.6304 5.50803V5.50803Z"
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: Math.max(18, Math.min(32, ((modelData && modelData.device_count) || 0) * 4 + 12))
                        height: 3
                        radius: 2
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: roomButton.bottom
                        anchors.topMargin: 4
                        color: "#65e0b5"
                        opacity: 0.9
                    }

                    Text {
                        width: parent.width
                        anchors.top: roomButton.bottom
                        anchors.topMargin: 12
                        horizontalAlignment: Text.AlignHCenter
                        text: root.deviceLabel(modelData)
                        color: root.themeTextColor
                        font.pixelSize: 10
                        font.bold: true
                        elide: Text.ElideRight
                    }
                }

                IconContainer {
                    visible: !(modelData && modelData.is_room) && !root.isSwitchboard(modelData)
                    device: root.currentDevice(modelData)
                    stateOverrideActive: true
                    stateOverrideOn: root.deviceIsOn(root.currentDevice(modelData))
                    text: root.deviceLabel(modelData)
                    delay: 160 + index * 80
                    iconSource: "qrc:/assets/icons/bulb.svg"
                    anchors.centerIn: parent
                    onClicked: root.deviceClicked(modelData)
                    onSpeedChanged: function(device, percentage) { root.deviceSetRequested(device, { percentage: percentage }) }
                }

                SwitchBoard {
                    visible: !(modelData && modelData.is_room) && root.isSwitchboard(modelData)
                    devices: root.currentSwitchboardDevices(modelData)
                    deviceStates: root.deviceStates
                    text: root.deviceLabel(modelData)
                    delay: 160 + index * 80
                    anchors.centerIn: parent
                    onDeviceClicked: function(device) { root.deviceClicked(device) }
                }
            }
        }

        Text {
            width: 320
            anchors.centerIn: parent
            visible: root.selectedRoomId ? root.devices.length === 0 : root.roomItems.length === 0
            text: root.selectedRoomId ? "No devices in this room" : "No Home Assistant rooms"
            color: root.themeMutedColor
            font.pixelSize: 11
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
        }
    }

    Button {
        id: backButton

        visible: root.selectedRoomId.length > 0
        variant: "ghost"
        darkMode: root.darkMode
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: 18
        anchors.leftMargin: 18 - root.navInset
        z: 82
        onClicked: root.backToRooms()

        contentItem: Component {
            Image {
                width: 24
                height: 24
                source: root.darkMode ? "qrc:/assets/icons/back.svg" : "qrc:/assets/icons/back-black.svg"
                fillMode: Image.PreserveAspectFit
                mipmap: true
                smooth: true
            }
        }
    }

    Button {
        id: refreshButton

        variant: "shadow"
        selected: root.refreshing
        darkMode: root.darkMode
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.margins: 18
        z: 80
        onClicked: root.refreshRequested()

        contentItem: Component {
            Item {
                id: iconBox

                width: 24
                height: 24

                RotationAnimator on rotation {
                    from: 0
                    to: 360
                    duration: 900
                    loops: Animation.Infinite
                    running: root.refreshing
                }

                Connections {
                    target: root

                    function onRefreshingChanged() {
                        if (!root.refreshing)
                            iconBox.rotation = 0
                    }
                }

                Shape {
                    anchors.fill: parent
                    antialiasing: true

                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: root.themeTextColor
                        strokeWidth: 2
                        capStyle: ShapePath.RoundCap
                        joinStyle: ShapePath.RoundJoin

                        PathSvg {
                            path: "M20.9844 6V10H17M20.9844 10L17.6569 6.34315C14.5327 3.21895 9.46734 3.21895 6.34315 6.34315C3.21895 9.46734 3.21895 14.5327 6.34315 17.6569C9.46734 20.781 14.5327 20.781 17.6569 17.6569C18.4407 16.873 19.0279 15.9669 19.4184 15"
                        }
                    }
                }
            }
        }
    }
}
