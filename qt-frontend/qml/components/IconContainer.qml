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
    readonly property bool isSocket: device && device.type === "switch"
    readonly property bool isOn: stateOverrideActive ? stateOverrideOn : (device && device.state && device.state.is_on)
    signal clicked()

    function deviceArtSource() {
        if (root.isLight)
            return root.isOn ? "BulbOn.qml" : "BulbOff.qml"
        if (root.isSocket)
            return root.isOn ? "SocketOn.qml" : "SocketOff.qml"
        return ""
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
            visible: !root.isLight && !root.isSocket
        }

        Loader {
            anchors.centerIn: parent
            width: root.isSocket ? 260 : 220
            height: root.isSocket ? 380 : 420
            scale: root.isSocket ? 0.125 : 0.144
            visible: root.isLight || root.isSocket
            source: root.deviceArtSource()
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
