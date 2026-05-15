import QtQuick
import QtQuick.Shapes
import "components"

Item {
    id: root

    property var devices: []
    property var deviceStates: ({})
    property bool refreshing: false
    signal deviceClicked(var device)
    signal refreshRequested()

    function deviceKey(device) {
        if (!device)
            return ""
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
                    room_name: device.room_name,
                    devices: []
                }
                order.push(groupKey)
            }
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

    function setDevices(nextDevices) {
        var unique = uniqueDeviceList(nextDevices || [])
        for (var i = 0; i < unique.length; i++)
            updateDevice(unique[i])

        var displayDevices = displayDeviceList(unique)
        if (!sameDeviceList(devices, displayDevices) || JSON.stringify(devices) !== JSON.stringify(displayDevices))
            devices = displayDevices
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
        if (device.room_name)
            return device.room_name
        return device.name || device.id || "Device"
    }

    function itemWidth(item) {
        if (isSwitchboard(item))
            return Math.max(132, ((item.devices || []).length * 46) + 22)
        return 132
    }

    function scatterX(index, areaWidth, visualWidth) {
        var positions = [0.10, 0.43, 0.76, 0.24, 0.61, 0.08, 0.44, 0.78, 0.27, 0.58, 0.14, 0.72]
        var base = positions[index % positions.length]
        var cycle = Math.floor(index / positions.length)
        var jitter = (((index * 37 + cycle * 19) % 25) - 12) / Math.max(1, areaWidth)
        return Math.max(10, Math.min(areaWidth - visualWidth - 10, (base + jitter) * areaWidth))
    }

    function scatterY(index, areaHeight) {
        var positions = [0.08, 0.18, 0.10, 0.36, 0.42, 0.62, 0.68, 0.58, 0.82, 0.78, 0.28, 0.88]
        var base = positions[index % positions.length]
        var cycle = Math.floor(index / positions.length)
        var jitter = (((index * 29 + cycle * 17) % 21) - 10) / Math.max(1, areaHeight)
        return Math.max(8, Math.min(areaHeight - 118, (base + jitter) * areaHeight))
    }

    Rectangle {
        anchors.fill: parent
        color: "#000000"
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
            color: "#334155"
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
            model: root.devices

            Item {
                width: root.itemWidth(modelData)
                height: 122
                x: root.scatterX(index, scatterLayer.width, width)
                y: root.scatterY(index, scatterLayer.height)

                IconContainer {
                    visible: !root.isSwitchboard(modelData)
                    device: modelData
                    stateOverrideActive: true
                    stateOverrideOn: root.deviceIsOn(modelData)
                    text: root.deviceLabel(modelData)
                    delay: 160 + index * 80
                    iconSource: "qrc:/assets/icons/bulb.svg"
                    anchors.centerIn: parent
                    onClicked: root.deviceClicked(modelData)
                }

                SwitchBoard {
                    visible: root.isSwitchboard(modelData)
                    devices: modelData.devices || []
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
            visible: root.devices.length === 0
            text: "No Home Assistant devices"
            color: "#71717a"
            font.pixelSize: 11
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
        }
    }

    Item {
        id: refreshButton

        width: 58
        height: 58
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 18
        z: 80
        opacity: tapHandler.pressed ? 0.72 : 1

        Rectangle {
            anchors.fill: parent
            radius: 8
            color: "#cc0b1518"
            border.color: root.refreshing ? "#69e8ff" : "#315c65"
            border.width: 1
        }

        Item {
            id: iconBox

            width: 150
            height: 150
            anchors.centerIn: parent
            scale: 0.27

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
                    strokeColor: root.refreshing ? "#69e8ff" : "#b8cbc8"
                    strokeWidth: 14
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin

                    PathSvg {
                        path: "M115 45 C95 20 55 18 32 42 C8 67 12 107 40 128 C68 149 108 143 128 115"
                    }
                }

                ShapePath {
                    fillColor: root.refreshing ? "#69e8ff" : "#b8cbc8"
                    strokeColor: "transparent"

                    PathSvg {
                        path: "M111 18 L136 48 L98 54 Z"
                    }
                }

                ShapePath {
                    fillColor: "transparent"
                    strokeColor: root.refreshing ? "#69e8ff" : "#b8cbc8"
                    strokeWidth: 14
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin

                    PathSvg {
                        path: "M35 105 C55 130 95 132 118 108 C142 83 138 43 110 22"
                    }
                }

                ShapePath {
                    fillColor: root.refreshing ? "#69e8ff" : "#b8cbc8"
                    strokeColor: "transparent"

                    PathSvg {
                        path: "M39 132 L14 102 L52 96 Z"
                    }
                }
            }
        }

        TapHandler {
            id: tapHandler

            acceptedDevices: PointerDevice.TouchScreen | PointerDevice.Mouse | PointerDevice.TouchPad
            onTapped: root.refreshRequested()
        }

        HoverHandler {
            cursorShape: Qt.PointingHandCursor
        }
    }
}
