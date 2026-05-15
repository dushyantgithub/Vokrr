import QtQuick

Item {
    id: root

    property var devices: []
    property var deviceStates: ({})
    property string text: ""
    property int delay: 0
    signal deviceClicked(var device)

    function deviceKey(device) {
        if (!device)
            return ""
        return device.id || (device.room_name + ":" + device.name)
    }

    function deviceIsOn(device) {
        var key = deviceKey(device)
        if (key && root.deviceStates.hasOwnProperty(key))
            return root.deviceStates[key]
        return !!(device && device.state && device.state.is_on)
    }

    function isSocketDevice(device) {
        if (!device || device.type !== "switch")
            return false
        var text = ((device.name || "") + " " + (device.entity_id || "")).toLowerCase()
        return text.indexOf("socket") !== -1
    }

    width: Math.max(132, switchRow.width + 20)
    height: 122
    opacity: 0
    scale: 0.86
    transformOrigin: Item.Center

    Rectangle {
        id: board

        width: Math.max(118, switchRow.width + 18)
        height: 88
        radius: 8

        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter

        gradient: Gradient {
            GradientStop { position: 0.0; color: "#ffffff" }
            GradientStop { position: 0.55; color: "#eeeeee" }
            GradientStop { position: 1.0; color: "#d8d8d8" }
        }
        border.color: "#aeb4bc"
        border.width: 1

        Row {
            id: switchRow

            height: 82
            spacing: 2
            anchors.centerIn: parent

            Repeater {
                model: root.devices

                Item {
                    width: root.isSocketDevice(modelData) ? 56 : 44
                    height: 82

                    SmartSwitch {
                        visible: !root.isSocketDevice(modelData)
                        anchors.centerIn: parent
                        scale: 0.25
                        isOn: root.deviceIsOn(modelData)
                        accentColor: "#44ff88"
                    }

                    Loader {
                        visible: root.isSocketDevice(modelData)
                        anchors.centerIn: parent
                        width: 260
                        height: 380
                        scale: 0.13
                        source: root.deviceIsOn(modelData) ? "SocketOn.qml" : "SocketOff.qml"
                    }

                    TapHandler {
                        acceptedDevices: PointerDevice.TouchScreen | PointerDevice.Mouse | PointerDevice.TouchPad
                        onTapped: root.deviceClicked(modelData)
                    }
                }
            }
        }
    }

    Text {
        width: parent.width
        anchors.top: board.bottom
        anchors.topMargin: 6
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.text
        font.pixelSize: 10
        font.bold: true
        color: "#94a3b8"
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
    }

    SequentialAnimation {
        running: true
        PauseAnimation { duration: root.delay }
        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "opacity"
                from: 0
                to: 1
                duration: 360
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: root
                property: "scale"
                from: 0.86
                to: 1
                duration: 420
                easing.type: Easing.OutBack
            }
        }
    }
}
