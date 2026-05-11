import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "components"

Window {
    id: root
    width: 800
    height: 480
    visible: true
    color: "#070a0f"
    title: "Vokrr"

    property date now: new Date()
    property string activeView: "Home"

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }

    ListModel {
        id: roomModel
        ListElement { name: "Living"; devices: 8; active: 4 }
        ListElement { name: "Bedroom"; devices: 5; active: 2 }
        ListElement { name: "Kitchen"; devices: 4; active: 1 }
        ListElement { name: "Studio"; devices: 6; active: 3 }
    }

    ListModel {
        id: deviceModel
        ListElement { name: "Main Lights"; type: "light"; enabled: true }
        ListElement { name: "Fan"; type: "switch"; enabled: false }
        ListElement { name: "AC"; type: "climate"; enabled: true }
        ListElement { name: "Door Lamp"; type: "light"; enabled: false }
        ListElement { name: "Purifier"; type: "fan"; enabled: true }
        ListElement { name: "Desk Light"; type: "light"; enabled: false }
    }

    ListModel {
        id: sceneModel
        ListElement { name: "Morning" }
        ListElement { name: "Movie" }
        ListElement { name: "Night" }
        ListElement { name: "Away" }
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#071019" }
            GradientStop { position: 0.55; color: "#090d13" }
            GradientStop { position: 1.0; color: "#05070b" }
        }
    }

    Rectangle {
        x: 122
        y: 34
        width: 520
        height: 1
        color: "#1d8090"
        opacity: 0.42
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.preferredWidth: 118
            Layout.fillHeight: true
            color: "#0b1119"
            border.color: "#1d2936"

            Column {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 14

                Rectangle {
                    width: 74
                    height: 48
                    radius: 8
                    color: "#101b27"
                    border.color: "#2ed7e7"

                    Text {
                        anchors.centerIn: parent
                        text: "VOKRR"
                        color: "#dffcff"
                        font.pixelSize: 16
                        font.weight: Font.Black
                    }
                }

                Repeater {
                    model: ["Home", "Rooms", "Scenes", "Settings"]
                    delegate: Rectangle {
                        width: 94
                        height: 50
                        radius: 8
                        color: root.activeView === modelData ? "#15313b" : "transparent"
                        border.color: root.activeView === modelData ? "#36e4d2" : "#1d2936"

                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            color: root.activeView === modelData ? "#ffffff" : "#8ea1b6"
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.activeView = modelData
                        }
                    }
                }

                Item { height: 8; width: 1 }

                Rectangle {
                    width: 94
                    height: 72
                    radius: 8
                    color: "#111822"
                    border.color: "#263748"

                    Column {
                        anchors.centerIn: parent
                        spacing: 4
                        Text { text: "HA"; color: "#37f2cd"; font.pixelSize: 20; font.weight: Font.Bold; anchors.horizontalCenter: parent.horizontalCenter }
                        Text { text: "online"; color: "#8ea1b6"; font.pixelSize: 11; anchors.horizontalCenter: parent.horizontalCenter }
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                anchors.fill: parent
                anchors.leftMargin: 18
                anchors.rightMargin: 16
                anchors.topMargin: 12
                anchors.bottomMargin: 0
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 72
                    spacing: 12

                    Column {
                        Layout.fillWidth: true
                        spacing: 4
                        Text {
                            text: Qt.formatTime(root.now, "hh:mm")
                            color: "#f8fcff"
                            font.pixelSize: 38
                            font.weight: Font.Light
                        }
                        Text {
                            text: Qt.formatDate(root.now, "dddd, dd MMMM")
                            color: "#8ea1b6"
                            font.pixelSize: 13
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 172
                        Layout.preferredHeight: 58
                        radius: 8
                        color: "#101924"
                        border.color: "#25374a"

                        Row {
                            anchors.centerIn: parent
                            spacing: 10
                            Text { text: "24C"; color: "#f4fbff"; font.pixelSize: 24; font.weight: Font.DemiBold }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2
                                Text { text: "Weather"; color: "#95aabe"; font.pixelSize: 12 }
                                Text { text: "Clear placeholder"; color: "#45ddff"; font.pixelSize: 11 }
                            }
                        }
                    }
                }

                Text {
                    text: "Rooms"
                    color: "#e9f9ff"
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                    Layout.preferredHeight: 18
                }

                Row {
                    Layout.preferredHeight: 82
                    Layout.fillWidth: true
                    spacing: 10

                    Repeater {
                        model: roomModel
                        delegate: RoomCard {
                            roomName: name
                            deviceCount: devices
                            activeDevices: active
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 20
                    Text {
                        Layout.fillWidth: true
                        text: "Devices"
                        color: "#e9f9ff"
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                    }
                    Text {
                        text: "touch to toggle"
                        color: "#71859c"
                        font.pixelSize: 11
                    }
                }

                Grid {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 222
                    columns: 3
                    columnSpacing: 10
                    rowSpacing: 10

                    Repeater {
                        model: deviceModel
                        delegate: DeviceCard {
                            deviceName: name
                            deviceType: type
                            deviceOn: enabled
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64
                    spacing: 10

                    Text {
                        Layout.preferredWidth: 92
                        text: "Scenes"
                        color: "#e9f9ff"
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                        verticalAlignment: Text.AlignVCenter
                    }

                    Repeater {
                        model: sceneModel
                        delegate: SceneCard {
                            sceneName: name
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 28
                    color: "#0b1119"
                    border.color: "#1d2936"
                    radius: 0

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 12

                        Text { text: "Wi-Fi: connected"; color: "#8ea1b6"; font.pixelSize: 11; Layout.fillWidth: true }
                        Text { text: "Home Assistant: ready"; color: "#37f2cd"; font.pixelSize: 11; Layout.fillWidth: true }
                        Text { text: "IP: 192.168.1.42"; color: "#8ea1b6"; font.pixelSize: 11; Layout.fillWidth: true; horizontalAlignment: Text.AlignRight }
                    }
                }
            }
        }
    }
}
