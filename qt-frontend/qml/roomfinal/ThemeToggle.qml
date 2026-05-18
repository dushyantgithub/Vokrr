import QtQuick

Item {
    id: root

    property var theme
    property bool checked: false
    signal toggled()

    width: 60
    height: 26

    Rectangle {
        id: switchFrame

        anchors.centerIn: parent
        width: 60
        height: 24
        radius: 15
        color: root.checked ? "#3300a85a" : "#33000000"
        border.width: 2
        border.color: root.checked ? "#3357d983" : "#1a3a3a3a"

        Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            radius: 12
            color: "transparent"
            border.width: 1
            border.color: root.checked ? "#224ade80" : "#22000000"
        }

        Rectangle {
            id: knob

            width: 26
            height: 18
            x: root.checked ? switchFrame.width - width - 3 : 3
            anchors.verticalCenter: parent.verticalCenter
            radius: 9
            border.width: 1
            border.color: root.checked ? "#0f5132" : "#1a1a1a"

            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0; color: root.checked ? "#74f2a9" : "#4f4f4f" }
                GradientStop { position: 1; color: root.checked ? "#25a85a" : "#2b2b2b" }
            }

            Behavior on x {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.InOutQuad
                }
            }

            Rectangle {
                x: 1
                y: 1
                width: 10
                height: 14
                radius: 6
                color: root.checked ? "#336eff9e" : "#66303030"
            }

            Rectangle {
                x: parent.width - width - 1
                y: 1
                width: 10
                height: 14
                radius: 6
                color: root.checked ? "#3325a85a" : "#66222222"
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggled()
        }
    }
}
