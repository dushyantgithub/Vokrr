import QtQuick

Item {
    id: root

    width: 190
    height: 254

    default property alias contentData: contentHost.data
    property color cardColor: "#212121"
    property color darkShadowColor: "#191919"
    property color lightShadowColor: "#3c3c3c"
    property real cornerRadius: 30

    Rectangle {
        anchors.fill: card
        anchors.leftMargin: 15
        anchors.topMargin: 15
        radius: root.cornerRadius
        color: root.darkShadowColor
        opacity: 0.9
    }

    Rectangle {
        anchors.fill: card
        anchors.leftMargin: -15
        anchors.topMargin: -15
        radius: root.cornerRadius
        color: root.lightShadowColor
        opacity: 0.9
    }

    Rectangle {
        id: card

        anchors.fill: parent
        radius: root.cornerRadius
        color: root.cardColor
        clip: true
    }

    Item {
        id: contentHost

        anchors.fill: card
    }
}
