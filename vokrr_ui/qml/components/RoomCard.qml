import QtQuick

Rectangle {
    id: root

    property string roomName: "Room"
    property int deviceCount: 0
    property int activeDevices: 0

    width: 142
    height: 78
    radius: 8
    color: "#141b25"
    border.color: "#29384a"
    border.width: 1

    Rectangle {
        width: Math.max(4, parent.width * Math.min(root.activeDevices / Math.max(root.deviceCount, 1), 1))
        height: 3
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        radius: 2
        color: "#32d4ff"
    }

    Column {
        anchors.fill: parent
        anchors.margins: 11
        spacing: 6

        Text {
            width: parent.width
            text: root.roomName
            color: "#f5fbff"
            font.pixelSize: 15
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }

        Text {
            text: root.activeDevices + " active / " + root.deviceCount + " devices"
            color: "#91a4b9"
            font.pixelSize: 11
        }
    }
}
