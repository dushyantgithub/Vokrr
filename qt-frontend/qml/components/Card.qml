import QtQuick
import QtQuick.Effects

Item {
    id: root

    width: 190
    height: 254

    default property alias contentData: contentHost.data
    property color cardColor: "#212121"
    property color darkShadowColor: "#191919"
    property color lightShadowColor: "#3c3c3c"
    property real cornerRadius: 30
    property real contentPadding: 0
    property real shadowOffset: 15
    property real shadowBlur: 0.85

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

    MultiEffect {
        anchors.fill: shadowShape
        source: shadowShape
        autoPaddingEnabled: true
        shadowEnabled: true
        shadowColor: root.lightShadowColor
        shadowOpacity: 1
        shadowBlur: root.shadowBlur
        shadowHorizontalOffset: -root.shadowOffset
        shadowVerticalOffset: -root.shadowOffset
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
