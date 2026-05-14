import QtQuick
import "components"

Item {
    id: root

    property var devices: []
    property var deviceStates: ({})
    signal deviceClicked(var device)

    function deviceKey(device) {
        if (!device)
            return ""
        return device.id || (device.room_name + ":" + device.name)
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
        if (!sameDeviceList(devices, unique))
            devices = unique
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
            return device.room_name + " " + device.name
        return device.name || device.id || "Device"
    }

    function scatterX(index, areaWidth) {
        var positions = [0.10, 0.43, 0.76, 0.24, 0.61, 0.08, 0.44, 0.78, 0.27, 0.58, 0.14, 0.72]
        var base = positions[index % positions.length]
        var cycle = Math.floor(index / positions.length)
        var jitter = (((index * 37 + cycle * 19) % 25) - 12) / Math.max(1, areaWidth)
        return Math.max(10, Math.min(areaWidth - 142, (base + jitter) * areaWidth))
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

            IconContainer {
                device: modelData
                stateOverrideActive: true
                stateOverrideOn: root.deviceIsOn(modelData)
                text: root.deviceLabel(modelData)
                delay: 160 + index * 80
                iconSource: "qrc:/assets/icons/bulb.svg"
                x: root.scatterX(index, scatterLayer.width)
                y: root.scatterY(index, scatterLayer.height)
                onClicked: root.deviceClicked(modelData)
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
}
