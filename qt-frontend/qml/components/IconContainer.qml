import QtQuick

Item {
    id: root

    property string text: ""
    property int delay: 0
    property url iconSource: ""
    property var device: null
    property bool stateOverrideActive: false
    property bool stateOverrideOn: false
    readonly property bool isLight: device && device.type === "light"
    readonly property bool isSwitchDevice: device && device.type === "switch"
    readonly property bool isSocket: root.isSwitchDevice && device && device.name && device.name.toLowerCase().indexOf("socket") !== -1
    readonly property bool isSwitch: root.isSwitchDevice && !root.isSocket
    readonly property bool isFan: device && device.type === "fan"
    readonly property bool isOn: stateOverrideActive ? stateOverrideOn : (device && device.state && device.state.is_on)
    readonly property bool isTubeLight: root.isLight && device && device.name && device.name.toLowerCase().indexOf("tubelight") !== -1
    signal clicked()

    function deviceArtSource() {
        if (root.isTubeLight)
            return root.isOn ? "TubeLightOn.qml" : "TubeLightOff.qml"
        if (root.isLight)
            return root.isOn ? "BulbOn.qml" : "BulbOff.qml"
        if (root.isSocket)
            return root.isOn ? "SocketOn.qml" : "SocketOff.qml"
        if (root.isSwitch)
            return "SmartSwitch.qml"
        if (root.isFan)
            return "CeilingFan.qml"
        return ""
    }

    function deviceLightColor() {
        if (device && device.state && device.state.rgb_color && device.state.rgb_color.length === 3)
            return Qt.rgba(device.state.rgb_color[0] / 255, device.state.rgb_color[1] / 255, device.state.rgb_color[2] / 255, 1)
        if (device && device.state && device.state.attributes && device.state.attributes.rgb_color && device.state.attributes.rgb_color.length === 3)
            return Qt.rgba(device.state.attributes.rgb_color[0] / 255, device.state.attributes.rgb_color[1] / 255, device.state.attributes.rgb_color[2] / 255, 1)
        if (device && device.state && device.state.attributes && device.state.attributes.hs_color && device.state.attributes.hs_color.length === 2)
            return Qt.hsva(device.state.attributes.hs_color[0] / 360, device.state.attributes.hs_color[1] / 100, 1, 1)
        return "#fff2c7"
    }

    function fanSpeed() {
        var percentage = device && device.state ? device.state.percentage : null
        if (percentage === null || percentage === undefined)
            return 1400
        return Math.max(650, 2600 - Math.round(percentage * 18))
    }

    width: 132
    height: 122
    opacity: 0
    scale: 0.86
    transformOrigin: Item.Center

    Item {
        id: iconArea

        width: 96
        height: 96
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter

        Image {
            width: 60
            height: 60
            anchors.centerIn: parent
            source: root.iconSource
            fillMode: Image.PreserveAspectFit
            opacity: 0.6
            mipmap: true
            smooth: true
            visible: !root.isLight && !root.isSwitchDevice && !root.isFan
        }

        Loader {
            id: deviceArt

            anchors.centerIn: parent
            width: root.isTubeLight ? 560 : (root.isSocket ? 260 : (root.isSwitch ? 180 : (root.isFan ? 520 : 220)))
            height: root.isTubeLight ? 140 : (root.isSocket ? 380 : (root.isSwitch ? 300 : (root.isFan ? 420 : 420)))
            scale: root.isTubeLight ? 0.17 : (root.isSocket ? 0.125 : (root.isSwitch ? 0.24 : (root.isFan ? 0.22 : 0.144)))
            visible: root.isLight || root.isSwitchDevice || root.isFan
            source: root.deviceArtSource()
        }

        Binding {
            target: deviceArt.item
            property: "lightColor"
            value: root.deviceLightColor()
            when: root.isTubeLight && root.isOn && deviceArt.item
        }

        Binding {
            target: deviceArt.item
            property: "spinning"
            value: root.isOn
            when: root.isFan && deviceArt.item
        }

        Binding {
            target: deviceArt.item
            property: "isOn"
            value: root.isOn
            when: root.isSwitch && deviceArt.item
        }

        Binding {
            target: deviceArt.item
            property: "speed"
            value: root.fanSpeed()
            when: root.isFan && deviceArt.item
        }
    }

    Text {
        width: parent.width
        anchors.top: iconArea.bottom
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

    TapHandler {
        acceptedDevices: PointerDevice.TouchScreen | PointerDevice.Mouse | PointerDevice.TouchPad
        onTapped: root.clicked()
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
