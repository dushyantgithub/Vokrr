import QtQuick
import QtQuick.Effects

Item {
    id: root

    width: 190
    height: 254

    default property alias contentData: contentHost.data
    property bool darkMode: true
    property color cardColor: darkMode ? "#212121" : "#e8e8e8"
    property color darkShadowColor: darkMode ? "#171717" : "#c5c5c5"
    property real cornerRadius: 30
    property real contentPadding: 0
    property real shadowOffset: 7.5
    property real shadowBlur: 0.425

    Rectangle {
        id: shadowShape

        anchors.fill: parent
        radius: root.cornerRadius
        color: root.cardColor
    }

    MultiEffect {
        anchors.fill: shadowShape
        source: shadowShape
        autoPaddingEnabled: true
        shadowEnabled: true
        shadowColor: root.darkShadowColor
        shadowOpacity: 1
        shadowBlur: root.shadowBlur
        shadowHorizontalOffset: root.shadowOffset
        shadowVerticalOffset: root.shadowOffset
    }

    Rectangle {
        id: cardFace

        anchors.fill: parent
        radius: root.cornerRadius
        color: root.cardColor
        clip: true
    }

    Item {
        id: contentHost

        anchors.fill: cardFace
        anchors.margins: root.contentPadding
    }
}
