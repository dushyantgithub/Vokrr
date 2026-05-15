import QtQuick

Item {
    id: root

    width: 54
    height: 54

    /*
        Variants:
        - light
        - shadow
        - ghost
        - default
    */

    property string variant: "light"
    property bool selected: false
    property alias contentItem: contentLoader.sourceComponent

    signal clicked()

    Rectangle {
        id: shadowLayer

        anchors.fill: buttonBg
        anchors.topMargin: root.variant === "shadow" ? 5 : 2

        radius: buttonBg.radius

        color: "#000000"
        opacity: root.variant === "shadow" ? 0.22 : 0.08

        visible: root.variant !== "ghost"
    }

    Rectangle {
        id: buttonBg

        width: Math.max(36, root.width - 8)
        height: Math.max(36, root.height - 8)
        radius: Math.min(14, height / 2)

        anchors.centerIn: parent

        scale: mouseArea.pressed ? 0.94 : 1

        color: {
            if (root.variant === "light")
                return root.selected ? "#dbeafe" : "#ffffff"

            if (root.variant === "shadow")
                return root.selected ? "#1f3d3a" : "#111717"

            if (root.variant === "ghost")
                return mouseArea.pressed || root.selected
                        ? "#f1f5f9"
                        : "transparent"

            return root.selected ? "#111827" : "#18181b"
        }

        border.width: root.variant === "ghost" ? 0 : 1

        border.color: {
            if (root.variant === "default")
                return "#27272a"

            if (root.variant === "light")
                return "#e5e7eb"

            if (root.variant === "shadow")
                return "#28413d"

            return "transparent"
        }

        Behavior on scale {
            NumberAnimation {
                duration: 110
                easing.type: Easing.OutQuad
            }
        }

        Behavior on color {
            ColorAnimation {
                duration: 160
            }
        }

        Loader {
            id: contentLoader
            anchors.centerIn: parent
        }
    }

    MouseArea {
        id: mouseArea

        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor

        onClicked: root.clicked()
    }
}
