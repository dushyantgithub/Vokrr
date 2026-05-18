import QtQuick
import "../components" as VokrrComponents

GlassPanel {
    id: root

    property var devices: []
    property string roomId: ""
    property int pageIndex: 0
    readonly property int pageCount: Math.max(1, Math.ceil(devices.length / 4))
    signal deviceActivated(var rawDevice)

    width: 356
    height: 164
    radius: theme.radiusXl
    padding: theme.space4

    onRoomIdChanged: pageIndex = 0
    onPageCountChanged: pageIndex = Math.max(0, Math.min(pageIndex, pageCount - 1))

    function pageDevices() {
        var start = pageIndex * 4
        return devices.slice(start, start + 4)
    }

    function move(delta) {
        pageIndex = Math.max(0, Math.min(pageIndex + delta, pageCount - 1))
    }

    Text {
        x: 0
        y: 0
        text: "Devices"
        color: theme.textPrimary
        font.family: theme.family()
        font.pixelSize: theme.headingMd
        font.bold: true
    }

    Text {
        x: 74
        y: 3
        width: 130
        text: devices.length + " in area"
        color: theme.textMuted
        font.family: theme.family()
        font.pixelSize: theme.bodySm
        elide: Text.ElideRight
    }

    Row {
        x: parent.width - width - (root.pageCount > 1 ? 70 : 0)
        y: 0
        spacing: theme.space2
        visible: root.pageCount > 1

        Repeater {
            model: root.pageCount
            Rectangle {
                width: index === root.pageIndex ? 16 : 6
                height: 6
                radius: theme.radiusFull
                color: index === root.pageIndex ? theme.accentCyan : theme.borderSubtle
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    Row {
        id: pagerButtons
        anchors.right: parent.right
        y: -4
        spacing: theme.space2
        visible: root.pageCount > 1

        VokrrComponents.Button {
            id: pagerLeft
            width: 30
            height: 30
            variant: "ghost"
            darkMode: theme.darkMode
            SvgIcon {
                anchors.centerIn: parent
                width: 16
                height: 16
                name: "chevron-left"
                iconColor: root.pageIndex > 0 ? theme.iconColor : theme.textDisabled
                darkMode: theme.darkMode
            }
            onClicked: root.move(-1)
        }

        VokrrComponents.Button {
            width: 30
            height: 30
            variant: "ghost"
            darkMode: theme.darkMode
            SvgIcon {
                anchors.centerIn: parent
                width: 16
                height: 16
                name: "chevron-right"
                iconColor: root.pageIndex < root.pageCount - 1 ? theme.iconColor : theme.textDisabled
                darkMode: theme.darkMode
            }
            onClicked: root.move(1)
        }
    }

    Grid {
        id: deviceGrid
        x: 0
        y: 30
        width: parent.width
        height: parent.height - 30
        columns: 2
        rowSpacing: theme.space4
        columnSpacing: theme.space4

        Repeater {
            model: root.pageDevices()
            DeviceCard {
                width: (deviceGrid.width - deviceGrid.columnSpacing) / 2
                height: (deviceGrid.height - deviceGrid.rowSpacing) / 2
                theme: root.theme
                deviceName: modelData.name
                meta: modelData.meta
                statusText: modelData.status
                deviceType: modelData.type
                deviceActive: modelData.active
                actionable: modelData.actionable
                rawDevice: modelData.raw
                onActivated: function(rawDevice) { root.deviceActivated(rawDevice) }
            }
        }
    }

}
