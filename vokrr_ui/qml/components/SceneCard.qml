import QtQuick

Rectangle {
    id: root

    property string sceneName: "Scene"
    signal activated()

    width: 132
    height: 58
    radius: 8
    color: tapArea.pressed ? "#273d51" : "#192332"
    border.color: "#33485d"
    border.width: 1
    scale: tapArea.pressed ? 0.98 : 1.0

    Behavior on scale { NumberAnimation { duration: 80 } }
    Behavior on color { ColorAnimation { duration: 120 } }

    Text {
        anchors.fill: parent
        anchors.margins: 10
        text: root.sceneName
        color: "#f5fbff"
        font.pixelSize: 14
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        wrapMode: Text.WordWrap
    }

    MouseArea {
        id: tapArea
        anchors.fill: parent
        onClicked: root.activated()
    }
}
