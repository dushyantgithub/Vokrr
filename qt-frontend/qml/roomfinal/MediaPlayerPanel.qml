import QtQuick
import "../components" as VokrrComponents

GlassPanel {
    id: root

    property string title: ""
    property string artist: ""
    property string album: ""
    property string albumArtUrl: ""
    property bool playing: false
    property bool connected: false
    signal mediaAction(string action)

    width: 184
    height: 74
    radius: theme.radiusXl - 2
    padding: theme.space5
    active: connected && title.length > 0

    readonly property bool hasMedia: connected && title.length > 0

    Rectangle {
        x: 0
        y: 0
        width: 42
        height: 42
        radius: theme.radiusSm
        color: theme.bgSurfaceSoft
        border.width: 0
        clip: true

        Image {
            anchors.fill: parent
            source: root.albumArtUrl
            visible: root.albumArtUrl.length > 0
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            smooth: true
        }

        SvgIcon {
            anchors.centerIn: parent
            width: 22
            height: 22
            name: "music"
            iconColor: theme.iconColor
            darkMode: theme.darkMode
            visible: root.albumArtUrl.length === 0
        }
    }

    Column {
        x: 50
        y: 0
        width: parent.width - 50
        spacing: 0
        Text {
            width: parent.width
            text: root.hasMedia ? root.title : "No media active"
            color: theme.textPrimary
            font.family: theme.family()
            font.pixelSize: theme.bodySm
            font.bold: true
            elide: Text.ElideRight
        }
        Text {
            width: parent.width
            text: root.hasMedia ? root.artist : "Start playback"
            color: theme.textSecondary
            font.family: theme.family()
            font.pixelSize: theme.caption
            elide: Text.ElideRight
        }
        Text {
            width: parent.width
            text: root.hasMedia ? root.album : ""
            color: theme.textMuted
            font.family: theme.family()
            font.pixelSize: theme.caption
            elide: Text.ElideRight
        }
    }

    Row {
        x: 50
        y: 28
        spacing: theme.space2
        width: parent.width - 50
        height: 24
        clip: true

        Repeater {
            model: [
                { icon: "skip-back", action: "previous" },
                { icon: root.playing ? "pause" : "play", action: "playPause" },
                { icon: "skip-forward", action: "next" }
            ]

            VokrrComponents.Button {
                width: Math.min(30, (parent.width - theme.space2 * 2) / 3)
                height: 24
                variant: "ghost"
                darkMode: theme.darkMode
                selected: modelData.action === "playPause" && root.playing
                opacity: root.connected ? 1 : 0.5
                SvgIcon {
                    anchors.centerIn: parent
                    width: 17
                    height: 17
                    name: modelData.icon
                    iconColor: theme.iconColor
                    darkMode: theme.darkMode
                }
                onClicked: {
                    if (root.connected)
                        root.mediaAction(modelData.action)
                }
            }
        }
    }
}
