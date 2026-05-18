import QtQuick
import "../components" as VokrrComponents

Item {
    id: root

    property var theme
    property var rooms: []
    property int currentRoomIndex: 0
    property int deviceCount: 0
    property string timeText: ""
    property string dateText: ""
    signal roomSelected(int index)
    signal themeRequested()

    height: 56
    readonly property int toggleWidth: 76
    readonly property int timeWidth: 144
    readonly property int headerGap: theme ? theme.space4 : 8

    function roomName() {
        if (!rooms || rooms.length === 0)
            return "No Rooms"
        var index = Math.max(0, Math.min(currentRoomIndex, rooms.length - 1))
        return rooms[index].name || "Room"
    }

    function move(delta) {
        if (!rooms || rooms.length === 0)
            return
        roomSelected((currentRoomIndex + delta + rooms.length) % rooms.length)
    }

    GlassPanel {
        x: 0
        y: 4
        width: Math.max(210, Math.min(300, parent.width - root.timeWidth - root.toggleWidth - root.headerGap * 2))
        height: 48
        theme: root.theme
        radius: theme.radiusMd
        padding: theme.space2
        active: true

        VokrrComponents.Button {
            x: 0
            y: 0
            width: 44
            height: 44
            variant: "ghost"
            darkMode: theme.darkMode
            SvgIcon {
                anchors.centerIn: parent
                width: 20
                height: 20
                name: "chevron-left"
                iconColor: theme.iconColor
                darkMode: theme.darkMode
            }
            onClicked: root.move(-1)
        }

        Column {
            x: 48
            y: 5
            width: parent.width - 96
            Text {
                width: parent.width
                text: root.roomName()
                color: theme.textPrimary
                font.family: theme.family()
                font.pixelSize: theme.headingMd
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: root.deviceCount + " devices"
                color: theme.textMuted
                font.family: theme.family()
                font.pixelSize: theme.caption
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }
        }

        VokrrComponents.Button {
            x: parent.width - 44
            y: 0
            width: 44
            height: 44
            variant: "ghost"
            darkMode: theme.darkMode
            SvgIcon {
                anchors.centerIn: parent
                width: 20
                height: 20
                name: "chevron-right"
                iconColor: theme.iconColor
                darkMode: theme.darkMode
            }
            onClicked: root.move(1)
        }

        MouseArea {
            anchors.fill: parent
            anchors.leftMargin: 44
            anchors.rightMargin: 44
            property real startX: 0
            onPressed: startX = mouse.x
            onReleased: {
                var delta = mouse.x - startX
                if (Math.abs(delta) > 28)
                    root.move(delta < 0 ? 1 : -1)
            }
        }
    }

    GlassPanel {
        x: Math.max(0, parent.width - root.toggleWidth - root.headerGap - root.timeWidth)
        y: 4
        width: root.timeWidth
        height: 48
        theme: root.theme
        radius: theme.radiusMd
        padding: 0
        Column {
            anchors.centerIn: parent
            width: parent.width
            spacing: 0
            Text {
                width: parent.width
                text: root.timeText
                color: theme.textPrimary
                font.family: theme.family()
                font.pixelSize: theme.numberMd
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }
            Text {
                width: parent.width
                text: root.dateText
                color: theme.textSecondary
                font.family: theme.family()
                font.pixelSize: theme.caption
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }
        }
    }

    ThemeToggle {
        x: parent.width - root.toggleWidth
        y: 15
        width: root.toggleWidth
        height: 26
        theme: root.theme
        checked: !theme.darkMode
        onToggled: root.themeRequested()
    }
}
