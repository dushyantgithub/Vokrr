import QtQuick
import QtQuick.Controls

Item {
    id: root
    clip: true

    property var rooms: []
    property var scenes: []
    property var health: null
    property string healthError: ""
    property string selectedRoomId: ""
    property string userName: "Ronit"
    property bool realtimeConnected: false
    property bool voicePipelineActive: false
    property string assistantStatus: "idle"
    property string assistantMessage: "waiting for wake-word"
    property string voiceStatusText: "waiting for wake-word"
    property bool mediaConnected: false
    property bool mediaPlaying: false
    property string mediaTitle: "Spotify"
    property string mediaArtist: ""
    property string mediaAlbum: ""
    property string mediaArtUrl: ""

    signal roomSelected(string roomId)
    signal deviceActionRequested(var device)
    signal deviceSetRequested(var device, var payload)
    signal mediaActionRequested(string action)
    signal sceneRequested(var scene)
    signal settingsRequested()

    property string currentScreen: "dashboard"
    property int selectedRoomIndex: 0
    property string clockText: ""
    property string dateText: ""
    property string compactDateText: ""

    readonly property color bgTop: "#0a0d0c"
    readonly property color bgMid: "#060807"
    readonly property color bgBottom: "#081210"
    readonly property color textPrimary: "#eef2ef"
    readonly property color textSecondary: "#c6cdc9"
    readonly property color textMuted: "#8a9691"
    readonly property color textDim: "#5f6b66"
    readonly property color accentGreen: "#2ec79a"
    readonly property color accentGreenDeep: "#114b3f"
    readonly property color accentGold: "#d9cba8"
    readonly property string displayFont: "Jost"
    readonly property string monoFont: "IBM Plex Mono"

    onRoomsChanged: syncRoomIndex()
    onSelectedRoomIdChanged: syncRoomIndex()

    Component.onCompleted: {
        updateClock()
        syncRoomIndex()
    }

    Timer {
        running: true
        repeat: true
        interval: 1000
        onTriggered: root.updateClock()
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0; color: root.currentScreen === "voice" ? "#0c1512" : root.bgTop }
            GradientStop { position: 0.58; color: root.bgMid }
            GradientStop { position: 1; color: root.bgBottom }
        }
    }

    Rectangle {
        width: parent.width * 0.72
        height: parent.height * 0.46
        radius: height / 2
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.currentScreen === "voice" ? parent.height * 0.14 : parent.height * 0.04
        color: "#142ec79a"
        opacity: root.currentScreen === "voice" ? 0.28 : 0.42
    }

    Loader {
        id: screenLoader
        anchors.fill: parent
        sourceComponent: root.currentScreen === "room"
            ? roomScreen
            : root.currentScreen === "health"
                ? healthScreen
                : root.currentScreen === "voice"
                    ? voiceScreen
                    : dashboardScreen
    }

    component Hairline: Rectangle {
        height: 1
        color: "#00ffffff"
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "#00d9cba8" }
            GradientStop { position: 0.5; color: "#38d9cba8" }
            GradientStop { position: 1; color: "#00d9cba8" }
        }
    }

    component GtPanel: Rectangle {
        id: panel
        property bool active: false
        property bool strong: false
        radius: 18
        color: active ? "#172ec79a" : "#06ffffff"
        border.width: 1
        border.color: active ? "#592ec79a" : "#24d9cba8"
        antialiasing: true
        gradient: strong ? strongGradient : null

        Gradient {
            id: strongGradient
            orientation: Gradient.Vertical
            GradientStop { position: 0; color: "#172ec79a" }
            GradientStop { position: 1; color: "#04ffffff" }
        }
    }

    component GtPill: Rectangle {
        id: pill
        property string label: ""
        property bool active: false
        property bool interactive: true
        signal clicked()

        height: 28
        radius: 14
        color: active ? "#152ec79a" : "#00ffffff"
        border.width: 1
        border.color: active ? "#662ec79a" : "#2ed9cba8"
        opacity: interactive ? 1 : 0.55

        Text {
            anchors.centerIn: parent
            width: parent.width - 14
            text: pill.label
            color: pill.active ? "#2ec79a" : "#8a9691"
            font.family: root.displayFont
            font.pixelSize: 11
            font.letterSpacing: 2
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }

        MouseArea {
            anchors.fill: parent
            enabled: pill.interactive
            onClicked: pill.clicked()
        }
    }

    component InstrumentDial: Item {
        id: dial
        property real progress: 0.5
        property string valueText: ""
        property string unitText: ""
        property string labelText: ""
        property string subText: ""
        property color accentColor: "#2ec79a"
        property color trackColor: "#22d9cba8"

        Canvas {
            id: dialCanvas
            anchors.fill: parent
            antialiasing: true
            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                var cx = width / 2
                var cy = height / 2
                var rOuter = Math.min(width, height) / 2 - 7
                var r = rOuter - 12
                var start = Math.PI * 0.73
                var span = Math.PI * 1.54
                ctx.lineCap = "round"
                ctx.lineWidth = 1
                ctx.strokeStyle = "#24d9cba8"
                ctx.beginPath()
                ctx.arc(cx, cy, rOuter, 0, Math.PI * 2)
                ctx.stroke()
                ctx.lineWidth = 10
                ctx.strokeStyle = dial.trackColor
                ctx.beginPath()
                ctx.arc(cx, cy, r, start, start + span)
                ctx.stroke()
                ctx.strokeStyle = dial.accentColor
                ctx.beginPath()
                ctx.arc(cx, cy, r, start, start + Math.max(0.02, Math.min(1, dial.progress)) * span)
                ctx.stroke()
                ctx.lineWidth = 1
                ctx.strokeStyle = "#55c6cdc9"
                var marks = [0, Math.PI / 2, Math.PI, Math.PI * 1.5]
                for (var i = 0; i < marks.length; i++) {
                    var a = marks[i]
                    ctx.beginPath()
                    ctx.moveTo(cx + Math.cos(a) * (rOuter - 7), cy + Math.sin(a) * (rOuter - 7))
                    ctx.lineTo(cx + Math.cos(a) * rOuter, cy + Math.sin(a) * rOuter)
                    ctx.stroke()
                }
            }
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            Connections {
                target: dial
                function onProgressChanged() { dialCanvas.requestPaint() }
                function onAccentColorChanged() { dialCanvas.requestPaint() }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height / 2 - 34
            text: dial.valueText
            color: "#eef2ef"
            font.family: root.displayFont
            font.pixelSize: 46
            font.weight: Font.ExtraLight
            horizontalAlignment: Text.AlignHCenter
        }

        Text {
            x: parent.width / 2 + 45
            y: parent.height / 2 - 20
            text: dial.unitText
            color: "#5f6b66"
            font.family: root.displayFont
            font.pixelSize: 16
            visible: dial.unitText.length > 0
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height / 2 + 24
            width: parent.width - 34
            text: dial.labelText
            color: "#8a9691"
            font.family: root.monoFont
            font.pixelSize: 9
            font.letterSpacing: 3
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height / 2 + 42
            width: parent.width - 30
            text: dial.subText
            color: dial.accentColor
            font.family: root.monoFont
            font.pixelSize: 9
            font.letterSpacing: 1
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
    }

    component SignalCore: Item {
        id: core
        property bool active: true
        property real coreSize: 44

        Rectangle {
            anchors.centerIn: parent
            width: parent.width
            height: parent.height
            radius: width / 2
            color: "#00ffffff"
            border.width: 1
            border.color: core.active ? "#732ec79a" : "#33d9cba8"
            opacity: core.active ? 0.9 : 0.35
            SequentialAnimation on scale {
                running: core.active
                loops: Animation.Infinite
                NumberAnimation { from: 0.86; to: 1.08; duration: 1500; easing.type: Easing.OutCubic }
                NumberAnimation { from: 1.08; to: 0.86; duration: 1500; easing.type: Easing.InOutQuad }
            }
        }

        Rectangle {
            anchors.centerIn: parent
            width: parent.width - 16
            height: width
            radius: width / 2
            color: "#00ffffff"
            border.width: 1
            border.color: "#33d9cba8"
        }

        Rectangle {
            anchors.centerIn: parent
            width: core.coreSize
            height: core.coreSize
            radius: width / 2
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0; color: core.active ? "#9defd0" : "#5f6b66" }
                GradientStop { position: 0.48; color: core.active ? "#2ec79a" : "#3c4642" }
                GradientStop { position: 1; color: core.active ? "#0d5b45" : "#111514" }
            }
            border.width: 1
            border.color: core.active ? "#552ec79a" : "#335f6b66"
            opacity: core.active ? 1 : 0.72
            scale: core.active ? 1 : 0.94
            SequentialAnimation on opacity {
                running: core.active
                loops: Animation.Infinite
                NumberAnimation { from: 0.78; to: 1; duration: 1400; easing.type: Easing.InOutQuad }
                NumberAnimation { from: 1; to: 0.78; duration: 1400; easing.type: Easing.InOutQuad }
            }
        }
    }

    component ToggleSwitch: Item {
        id: sw
        property bool checked: false
        width: 50
        height: 28

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: sw.checked ? "#2ec79a" : "#12ffffff"
            border.width: sw.checked ? 0 : 1
            border.color: "#29d9cba8"
        }

        Rectangle {
            y: 3
            x: sw.checked ? parent.width - width - 3 : 3
            width: sw.checked ? 22 : 18
            height: sw.checked ? 22 : 18
            radius: width / 2
            color: sw.checked ? "#07100c" : "#8a9691"
            Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on width { NumberAnimation { duration: 140 } }
            Behavior on height { NumberAnimation { duration: 140 } }
        }
    }

    component SparkLine: Canvas {
        id: spark
        property color lineColor: "#2ec79a"
        property var points: [42, 40, 44, 34, 47, 50, 52, 46, 24, 17, 31, 38, 33, 41, 37, 43, 39]

        antialiasing: true
        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            if (!points || points.length < 2)
                return
            var step = width / (points.length - 1)
            ctx.lineWidth = 1.6
            ctx.lineCap = "round"
            ctx.strokeStyle = spark.lineColor
            ctx.beginPath()
            for (var i = 0; i < points.length; i++) {
                var x = i * step
                var y = Math.max(4, Math.min(height - 4, points[i] / 60 * height))
                if (i === 0)
                    ctx.moveTo(x, y)
                else
                    ctx.lineTo(x, y)
            }
            ctx.stroke()
            ctx.lineTo(width, height)
            ctx.lineTo(0, height)
            ctx.closePath()
            ctx.fillStyle = "#102ec79a"
            ctx.fill()
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
    }

    Component {
        id: dashboardScreen

        Item {
            anchors.fill: parent

            Item {
                x: 26
                y: 18
                width: parent.width - 52
                height: 32

                Text {
                    x: 0
                    width: 88
                    height: parent.height
                    text: "VOKRR"
                    color: root.accentGold
                    font.family: root.displayFont
                    font.pixelSize: 15
                    font.weight: Font.Light
                    font.letterSpacing: 6
                    verticalAlignment: Text.AlignVCenter

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.settingsRequested()
                    }
                }

                Rectangle {
                    x: 106
                    width: 1
                    height: 14
                    anchors.verticalCenter: parent.verticalCenter
                    color: "#40d9cba8"
                }

                Text {
                    x: 124
                    width: 180
                    height: parent.height
                    text: root.dateText
                    color: root.textDim
                    font.family: root.monoFont
                    font.pixelSize: 11
                    font.letterSpacing: 2
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }

                Text {
                    x: parent.width - 262
                    width: 118
                    height: parent.height
                    text: root.clockText
                    color: root.textPrimary
                    font.family: root.displayFont
                    font.pixelSize: 30
                    font.weight: Font.ExtraLight
                    font.letterSpacing: 3
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                }

                Text {
                    x: parent.width - 128
                    width: 128
                    height: parent.height
                    text: root.weatherLabel()
                    color: root.textDim
                    font.family: root.monoFont
                    font.pixelSize: 11
                    font.letterSpacing: 1
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideRight
                }
            }

            Hairline {
                x: 26
                y: 60
                width: parent.width - 52
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 92
                spacing: 34
                height: 196

                InstrumentDial {
                    width: 196
                    height: 196
                    progress: Math.min(1, root.homeLoadWatts() / 550)
                    valueText: String(root.homeLoadWatts())
                    unitText: "W"
                    labelText: "HOME LOAD"
                    subText: root.activeDeviceCount(root.allDevices()) + " OF " + root.allDevices().length + " ACTIVE"
                    accentColor: root.accentGreen
                    trackColor: "#22114b3f"
                }

                Item {
                    width: 250
                    height: 196

                    SignalCore {
                        width: 74
                        height: 74
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 2
                        active: root.voicePipelineActive || root.realtimeConnected
                        coreSize: 44

                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.currentScreen = "voice"
                        }
                    }

                    Text {
                        x: 0
                        y: 92
                        width: parent.width
                        text: root.greetingText()
                        color: root.textPrimary
                        font.family: root.displayFont
                        font.pixelSize: 19
                        font.weight: Font.Light
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }

                    Text {
                        x: 12
                        y: 122
                        width: parent.width - 24
                        text: root.summaryText()
                        color: root.textMuted
                        font.family: root.displayFont
                        font.pixelSize: 13
                        font.weight: Font.Light
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        lineHeight: 1.12
                    }

                    Rectangle {
                        width: 150
                        height: 30
                        radius: 15
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 164
                        color: "#00ffffff"
                        border.width: 1
                        border.color: "#48d9cba8"

                        Text {
                            anchors.centerIn: parent
                            width: parent.width - 18
                            text: root.voicePipelineActive ? root.voiceStatusText.toUpperCase() : "SAY JARVIS"
                            color: root.accentGold
                            font.family: root.monoFont
                            font.pixelSize: 10
                            font.letterSpacing: 2
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.currentScreen = "voice"
                        }
                    }
                }

                InstrumentDial {
                    width: 196
                    height: 196
                    progress: root.recoveryScore() / 100
                    valueText: String(root.recoveryScore())
                    unitText: ""
                    labelText: "RECOVERY"
                    subText: "HR " + root.heartRate() + " - SLEEP " + root.sleepDuration()
                    accentColor: root.accentGold
                    trackColor: "#22d9cba8"
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 92
                color: "#dd070908"
                border.width: 1
                border.color: "#24d9cba8"

                Rectangle {
                    anchors.fill: parent
                    color: "#12114b3f"
                }

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 26
                    anchors.rightMargin: 26
                    anchors.topMargin: 12
                    anchors.bottomMargin: 16
                    spacing: 12

                    Repeater {
                        model: root.dashboardDockModel()

                        GtPanel {
                            width: modelData.kind === "room" ? 184 : 142
                            height: parent.height
                            radius: 14
                            active: modelData.active

                            Column {
                                x: 16
                                y: 10
                                width: parent.width - 46
                                spacing: 2

                                Text {
                                    width: parent.width
                                    text: modelData.title
                                    color: modelData.kind === "scene" || modelData.kind === "health" ? root.accentGold : root.textPrimary
                                    font.family: root.displayFont
                                    font.pixelSize: 14
                                    font.letterSpacing: 1
                                    elide: Text.ElideRight
                                }

                                Text {
                                    width: parent.width
                                    text: modelData.subtitle
                                    color: root.textMuted
                                    font.family: root.monoFont
                                    font.pixelSize: 9
                                    elide: Text.ElideRight
                                }
                            }

                            Rectangle {
                                width: 8
                                height: 8
                                radius: 4
                                anchors.right: parent.right
                                anchors.rightMargin: 18
                                anchors.verticalCenter: parent.verticalCenter
                                visible: modelData.kind === "room"
                                color: modelData.active ? root.accentGreen : root.textDim
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.handleDockAction(modelData)
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: roomScreen

        Item {
            id: roomPage
            anchors.fill: parent
            readonly property var room: root.selectedRoom()
            readonly property var hero: root.primaryDevice(room)
            readonly property var cards: root.secondaryDeviceCards(room, hero)

            Rectangle {
                x: 26
                y: 18
                width: 40
                height: 40
                radius: 20
                color: "#00ffffff"
                border.width: 1
                border.color: "#4dd9cba8"

                Text {
                    anchors.centerIn: parent
                    text: "<"
                    color: root.accentGold
                    font.family: root.displayFont
                    font.pixelSize: 18
                    font.weight: Font.Light
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.currentScreen = "dashboard"
                }
            }

            Column {
                x: 82
                y: 18
                width: 290
                spacing: 2

                Text {
                    width: parent.width
                    text: root.roomName(room)
                    color: root.textPrimary
                    font.family: root.displayFont
                    font.pixelSize: 24
                    font.weight: Font.Light
                    font.letterSpacing: 2
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    text: root.roomMeta(room)
                    color: root.textDim
                    font.family: root.monoFont
                    font.pixelSize: 9
                    font.letterSpacing: 2
                    elide: Text.ElideRight
                }
            }

            Flickable {
                x: 390
                y: 23
                width: parent.width - x - 26
                height: 30
                clip: true
                contentWidth: roomPills.implicitWidth
                contentHeight: height
                boundsBehavior: Flickable.StopAtBounds

                Row {
                    id: roomPills
                    height: parent.height
                    spacing: 8

                    Repeater {
                        model: root.roomPillModel()
                        GtPill {
                            width: Math.max(82, Math.min(118, modelData.name.length * 8 + 26))
                            label: root.compactRoomLabel(modelData.name)
                            active: modelData.index === root.selectedRoomIndex
                            onClicked: root.setRoomIndex(modelData.index)
                        }
                    }
                }
            }

            Hairline {
                x: 26
                y: 72
                width: parent.width - 52
            }

            GtPanel {
                x: 26
                y: 86
                width: 296
                height: 360
                active: root.deviceIsOn(roomPage.hero)
                strong: true

                Text {
                    x: 18
                    y: 17
                    width: parent.width - 92
                    text: root.deviceTitle(roomPage.hero, "Tubelight")
                    color: root.textPrimary
                    font.family: root.displayFont
                    font.pixelSize: 17
                    font.letterSpacing: 1
                    elide: Text.ElideRight
                }

                Text {
                    x: 18
                    y: 42
                    width: parent.width - 92
                    text: root.lightMeta(roomPage.hero)
                    color: root.textMuted
                    font.family: root.monoFont
                    font.pixelSize: 9
                    elide: Text.ElideRight
                }

                ToggleSwitch {
                    x: parent.width - 68
                    y: 18
                    checked: root.deviceIsOn(roomPage.hero)
                }

                MouseArea {
                    x: parent.width - 76
                    y: 10
                    width: 68
                    height: 46
                    enabled: !!roomPage.hero
                    onClicked: root.deviceActionRequested(roomPage.hero)
                }

                Text {
                    x: 18
                    y: 188
                    text: root.levelFor(roomPage.hero)
                    color: root.textPrimary
                    font.family: root.displayFont
                    font.pixelSize: 44
                    font.weight: Font.ExtraLight
                }

                Text {
                    x: 84
                    y: 211
                    text: "%"
                    color: root.textDim
                    font.family: root.displayFont
                    font.pixelSize: 18
                }

                Rectangle {
                    id: levelTrack
                    x: 18
                    y: 260
                    width: parent.width - 36
                    height: 6
                    radius: 3
                    color: "#12ffffff"

                    Rectangle {
                        width: levelTrack.width * root.levelFor(roomPage.hero) / 100
                        height: parent.height
                        radius: 3
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: root.accentGreenDeep }
                            GradientStop { position: 1; color: root.accentGreen }
                        }
                    }

                    Rectangle {
                        width: 16
                        height: 16
                        radius: 8
                        y: -5
                        x: Math.max(0, Math.min(levelTrack.width - width, levelTrack.width * root.levelFor(roomPage.hero) / 100 - 8))
                        color: root.textPrimary
                    }

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -12
                        enabled: !!roomPage.hero
                        onPressed: function(mouse) { root.commitLevel(roomPage.hero, mouse.x + 12, levelTrack.width) }
                        onPositionChanged: function(mouse) {
                            if (pressed)
                                root.commitLevel(roomPage.hero, mouse.x + 12, levelTrack.width)
                        }
                        onReleased: function(mouse) { root.commitLevel(roomPage.hero, mouse.x + 12, levelTrack.width) }
                    }
                }

                Row {
                    x: 18
                    y: 300
                    width: parent.width - 36
                    height: 36
                    spacing: 8

                    Repeater {
                        model: [
                            { label: "WARM", active: false },
                            { label: "NEUTRAL", active: true },
                            { label: "COOL", active: false }
                        ]

                        Rectangle {
                            width: (parent.width - 16) / 3
                            height: 36
                            radius: 10
                            color: modelData.active ? "#172ec79a" : "#00ffffff"
                            border.width: 1
                            border.color: modelData.active ? "#732ec79a" : "#2ed9cba8"

                            Text {
                                anchors.centerIn: parent
                                width: parent.width - 8
                                text: modelData.label
                                color: modelData.active ? root.accentGreen : root.textMuted
                                font.family: root.displayFont
                                font.pixelSize: 11
                                font.letterSpacing: 1.5
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }

            Grid {
                x: 334
                y: 86
                width: 440
                height: 360
                columns: 2
                columnSpacing: 12
                rowSpacing: 12

                Repeater {
                    model: roomPage.cards

                    GtPanel {
                        width: 214
                        height: 174
                        radius: 18
                        active: modelData.active

                        Text {
                            x: 16
                            y: 15
                            width: parent.width - 32
                            text: modelData.name
                            color: root.textPrimary
                            font.family: root.displayFont
                            font.pixelSize: 14
                            elide: Text.ElideRight
                        }

                        Text {
                            x: 16
                            y: 38
                            width: parent.width - 32
                            text: modelData.meta
                            color: root.textDim
                            font.family: root.monoFont
                            font.pixelSize: 9
                            elide: Text.ElideRight
                        }

                        Text {
                            x: 16
                            y: parent.height - 38
                            text: modelData.status
                            color: modelData.active ? root.accentGreen : root.textDim
                            font.family: root.monoFont
                            font.pixelSize: 9
                        }

                        ToggleSwitch {
                            x: parent.width - 60
                            y: parent.height - 48
                            width: 44
                            height: 24
                            checked: modelData.active
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: !!modelData.raw
                            onClicked: root.deviceActionRequested(modelData.raw)
                        }
                    }
                }
            }
        }
    }

    Component {
        id: healthScreen

        Item {
            anchors.fill: parent

            Rectangle {
                x: 26
                y: 18
                width: 40
                height: 40
                radius: 20
                color: "#00ffffff"
                border.width: 1
                border.color: "#4dd9cba8"

                Text {
                    anchors.centerIn: parent
                    text: "<"
                    color: root.accentGold
                    font.family: root.displayFont
                    font.pixelSize: 18
                    font.weight: Font.Light
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.currentScreen = "dashboard"
                }
            }

            Text {
                x: 82
                y: 17
                width: 120
                text: "Health"
                color: root.textPrimary
                font.family: root.displayFont
                font.pixelSize: 24
                font.weight: Font.Light
                font.letterSpacing: 2
            }

            Text {
                x: 206
                y: 28
                width: 270
                text: root.healthSyncLabel()
                color: root.textDim
                font.family: root.monoFont
                font.pixelSize: 9
                font.letterSpacing: 2
                elide: Text.ElideRight
            }

            Row {
                x: 606
                y: 22
                spacing: 8

                GtPill { width: 78; label: "TODAY"; active: true; interactive: false }
                GtPill { width: 78; label: "WEEK"; active: false; interactive: false }
            }

            Hairline {
                x: 26
                y: 72
                width: parent.width - 52
            }

            GtPanel {
                x: 26
                y: 86
                width: 225
                height: 360
                radius: 18

                InstrumentDial {
                    width: 142
                    height: 142
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 48
                    progress: root.recoveryScore() / 100
                    valueText: String(root.recoveryScore())
                    unitText: ""
                    labelText: "RECOVERY"
                    subText: ""
                    accentColor: root.accentGold
                    trackColor: "#22d9cba8"
                }

                Text {
                    x: 20
                    y: 208
                    width: parent.width - 40
                    text: "Ready for strain"
                    color: root.accentGold
                    font.family: root.displayFont
                    font.pixelSize: 14
                    font.weight: Font.Light
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }

                Row {
                    x: 18
                    y: 248
                    width: parent.width - 36
                    height: 54
                    spacing: 12

                    Repeater {
                        model: [
                            { value: "58", label: "HRV MS" },
                            { value: "36.4", label: "SKIN" },
                            { value: "31%", label: "RING" }
                        ]

                        Column {
                            width: (parent.width - 24) / 3
                            spacing: 2

                            Text {
                                width: parent.width
                                text: modelData.value
                                color: root.textPrimary
                                font.family: root.displayFont
                                font.pixelSize: 18
                                font.weight: Font.Light
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                text: modelData.label
                                color: root.textDim
                                font.family: root.monoFont
                                font.pixelSize: 8
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }

            Column {
                x: 265
                y: 86
                width: 509
                height: 360
                spacing: 12

                GtPanel {
                    width: parent.width
                    height: 198
                    radius: 18

                    Text {
                        x: 18
                        y: 14
                        width: 220
                        text: "HEART RATE - 24H"
                        color: root.textDim
                        font.family: root.monoFont
                        font.pixelSize: 9
                        font.letterSpacing: 2
                    }

                    Text {
                        x: parent.width - 116
                        y: 8
                        width: 98
                        text: root.heartRate() + " BPM"
                        color: root.accentGreen
                        font.family: root.displayFont
                        font.pixelSize: 22
                        font.weight: Font.Light
                        horizontalAlignment: Text.AlignRight
                    }

                    SparkLine {
                        x: 18
                        y: 50
                        width: parent.width - 36
                        height: 104
                    }

                    Row {
                        x: 18
                        y: 162
                        width: parent.width - 36
                        height: 16
                        spacing: 0

                        Repeater {
                            model: ["00:00", "06:00", "12:00", "18:00", "NOW"]
                            Text {
                                width: parent.width / 5
                                text: modelData
                                color: "#3c4642"
                                font.family: root.monoFont
                                font.pixelSize: 8
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }
                }

                GtPanel {
                    width: parent.width
                    height: 150
                    radius: 18

                    Text {
                        x: 18
                        y: 15
                        width: 200
                        text: "SLEEP - LAST NIGHT"
                        color: root.textDim
                        font.family: root.monoFont
                        font.pixelSize: 9
                        font.letterSpacing: 2
                    }

                    Text {
                        x: parent.width - 170
                        y: 10
                        width: 152
                        text: root.sleepDuration() + " - 88"
                        color: root.textPrimary
                        font.family: root.displayFont
                        font.pixelSize: 18
                        font.weight: Font.Light
                        horizontalAlignment: Text.AlignRight
                    }

                    Row {
                        x: 18
                        y: 62
                        width: parent.width - 36
                        height: 14
                        spacing: 0

                        Repeater {
                            model: [
                                { w: 0.14, c: "#114b3f" },
                                { w: 0.24, c: "#1c8a68" },
                                { w: 0.10, c: "#2ec79a" },
                                { w: 0.20, c: "#1c8a68" },
                                { w: 0.08, c: "#114b3f" },
                                { w: 0.14, c: "#2ec79a" },
                                { w: 0.10, c: "#1c8a68" }
                            ]

                            Rectangle {
                                width: (parent ? parent.width : 470) * modelData.w
                                height: 14
                                radius: index === 0 || index === 6 ? 7 : 0
                                color: modelData.c
                            }
                        }
                    }

                    Row {
                        x: 18
                        y: 98
                        spacing: 16

                        Repeater {
                            model: [
                                { c: "#2ec79a", label: "DEEP 1H50" },
                                { c: "#1c8a68", label: "LIGHT 4H10" },
                                { c: "#114b3f", label: "REM 1H42" }
                            ]

                            Row {
                                spacing: 6
                                Rectangle {
                                    width: 7
                                    height: 7
                                    radius: 4
                                    color: modelData.c
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: modelData.label
                                    color: root.textDim
                                    font.family: root.monoFont
                                    font.pixelSize: 8
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: voiceScreen

        Item {
            anchors.fill: parent

            Row {
                x: 30
                y: 22
                width: parent.width - 60
                height: 18

                Row {
                    width: 250
                    height: parent.height
                    spacing: 8
                    Rectangle {
                        width: 6
                        height: 6
                        radius: 3
                        color: root.voicePipelineActive ? root.accentGreen : root.textDim
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        width: 230
                        text: root.voicePipelineActive ? root.voiceStatusText.toUpperCase() : "STANDBY"
                        color: root.voicePipelineActive ? root.accentGreen : root.textDim
                        font.family: root.monoFont
                        font.pixelSize: 9
                        font.letterSpacing: 3
                        elide: Text.ElideRight
                    }
                }

                Text {
                    width: parent.width - 250
                    text: root.clockText
                    color: root.accentGold
                    font.family: root.monoFont
                    font.pixelSize: 9
                    font.letterSpacing: 3
                    horizontalAlignment: Text.AlignRight
                }
            }

            SignalCore {
                width: 150
                height: 150
                anchors.horizontalCenter: parent.horizontalCenter
                y: 82
                active: root.voicePipelineActive
                coreSize: 78
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 258
                width: 40
                height: 24
                spacing: 4

                Repeater {
                    model: [0.4, 0.75, 1.0, 0.65, 0.45]

                    Rectangle {
                        width: 3
                        height: 24 * modelData
                        radius: 2
                        anchors.verticalCenter: parent.verticalCenter
                        color: index === 0 || index === 4 ? root.accentGold : root.accentGreen
                        transformOrigin: Item.Bottom
                        opacity: root.voicePipelineActive ? 1 : 0.35

                        SequentialAnimation on scale {
                            running: root.voicePipelineActive
                            loops: Animation.Infinite
                            PauseAnimation { duration: index * 120 }
                            NumberAnimation { from: 0.55; to: 1.15; duration: 480; easing.type: Easing.InOutQuad }
                            NumberAnimation { from: 1.15; to: 0.55; duration: 480; easing.type: Easing.InOutQuad }
                        }
                    }
                }
            }

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 304
                width: 560
                spacing: 12

                Text {
                    width: parent.width
                    text: root.voicePromptText()
                    color: root.textDim
                    font.family: root.monoFont
                    font.pixelSize: 11
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    text: root.voiceReplyText()
                    color: root.textPrimary
                    font.family: root.displayFont
                    font.pixelSize: 24
                    font.weight: Font.Light
                    lineHeight: 1.12
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 24
                spacing: 10

                GtPill {
                    width: 168
                    label: root.voicePipelineActive ? "VOICE ONLINE" : "SOCKETS READY"
                    active: true
                    interactive: false
                }

                GtPill {
                    width: 156
                    label: "TAP TO DISMISS"
                    active: false
                    onClicked: root.currentScreen = "dashboard"
                }
            }

            MouseArea {
                anchors.fill: parent
                z: -1
                onClicked: root.currentScreen = "dashboard"
            }
        }
    }

    function updateClock() {
        var now = new Date()
        var hh = String(now.getHours()).padStart(2, "0")
        var mm = String(now.getMinutes()).padStart(2, "0")
        var days = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
        var months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
        clockText = hh + ":" + mm
        dateText = days[now.getDay()] + " " + now.getDate() + " " + months[now.getMonth()]
        compactDateText = now.getDate() + " " + months[now.getMonth()]
    }

    function syncRoomIndex() {
        if (!rooms || rooms.length === 0) {
            selectedRoomIndex = 0
            return
        }
        if (!selectedRoomId)
            selectedRoomId = preferredRoomIndices()[0] !== undefined ? rooms[preferredRoomIndices()[0]].id : rooms[0].id
        for (var i = 0; i < rooms.length; i++) {
            if (rooms[i] && rooms[i].id === selectedRoomId) {
                selectedRoomIndex = i
                return
            }
        }
    }

    function setRoomIndex(index) {
        if (!rooms || rooms.length === 0)
            return
        selectedRoomIndex = Math.max(0, Math.min(rooms.length - 1, index))
        var room = selectedRoom()
        if (room && room.id)
            roomSelected(room.id)
    }

    function selectedRoom() {
        if (!rooms || rooms.length === 0)
            return null
        var index = Math.max(0, Math.min(rooms.length - 1, selectedRoomIndex))
        return rooms[index]
    }

    function allDevices() {
        var out = []
        if (!rooms)
            return out
        for (var i = 0; i < rooms.length; i++) {
            var devices = rooms[i] && rooms[i].devices ? rooms[i].devices : []
            for (var j = 0; j < devices.length; j++)
                out.push(devices[j])
        }
        return out
    }

    function visibleDevices(room) {
        var devices = room && room.devices ? room.devices : []
        var out = []
        for (var i = 0; i < devices.length; i++) {
            if (devices[i] && devices[i].state)
                out.push(devices[i])
        }
        return out
    }

    function roomRank(room) {
        var name = String(roomName(room)).toLowerCase()
        if (name.indexOf("gaming") !== -1 || name.indexOf("game") !== -1)
            return 0
        if (name.indexOf("bed") !== -1)
            return 1
        if (name.indexOf("living") !== -1 || name.indexOf("hall") !== -1)
            return 2
        if (name.indexOf("kitchen") !== -1)
            return 3
        if (name.indexOf("dining") !== -1)
            return 4
        if (name.indexOf("bath") !== -1)
            return 5
        return 8
    }

    function preferredRoomIndices() {
        var out = []
        if (!rooms)
            return out
        for (var i = 0; i < rooms.length; i++)
            out.push({ index: i, rank: roomRank(rooms[i]), devices: visibleDevices(rooms[i]).length })
        out.sort(function(a, b) {
            if (a.rank !== b.rank)
                return a.rank - b.rank
            if (a.devices !== b.devices)
                return b.devices - a.devices
            return a.index - b.index
        })
        var indices = []
        for (var j = 0; j < out.length; j++)
            indices.push(out[j].index)
        return indices
    }

    function activeDeviceCount(devices) {
        var count = 0
        var list = devices || []
        for (var i = 0; i < list.length; i++) {
            if (deviceIsOn(list[i]))
                count++
        }
        return count
    }

    function roomName(room) {
        if (room && room.name)
            return room.name
        return "Bedroom"
    }

    function compactRoomLabel(name) {
        var raw = String(name || "Room")
        var lower = raw.toLowerCase()
        if (lower.indexOf("living") !== -1)
            return "LIVING"
        if (lower.indexOf("gaming") !== -1 || lower.indexOf("game") !== -1)
            return "GAMING"
        if (lower.indexOf("dining") !== -1)
            return "DINING"
        if (lower.indexOf("bed") !== -1)
            return "BEDROOM"
        if (lower.indexOf("bath") !== -1)
            return "BATH"
        return raw.toUpperCase()
    }

    function roomPillModel() {
        var out = []
        var order = preferredRoomIndices()
        for (var i = 0; i < order.length; i++) {
            var index = order[i]
            out.push({ name: roomName(rooms[index]), index: index })
        }
        if (out.length === 0) {
            out.push({ name: "Gaming", index: 1 })
            out.push({ name: "Bedroom", index: 0 })
        }
        return out
    }

    function roomMeta(room) {
        var devices = visibleDevices(room)
        return roomTemperature(room) + " - " + roomLoadWatts(room) + "W - " + activeDeviceCount(devices) + " OF " + devices.length + " ACTIVE"
    }

    function roomTemperature(room) {
        var devices = visibleDevices(room)
        for (var i = 0; i < devices.length; i++) {
            var attrs = devices[i].state && devices[i].state.attributes ? devices[i].state.attributes : {}
            var klass = String(attrs.device_class || "").toLowerCase()
            var unit = String(attrs.unit_of_measurement || "").toLowerCase()
            var value = devices[i].state ? devices[i].state.state : null
            if (klass === "temperature" || unit.indexOf("deg") !== -1 || unit.indexOf("c") !== -1)
                return String(value).replace("unknown", "21.4") + "C"
        }
        return roomName(room).toLowerCase().indexOf("bed") !== -1 ? "21.4C" : "24.1C"
    }

    function hasCapability(device, capability) {
        return !!(device && device.capabilities && device.capabilities.indexOf(capability) !== -1)
    }

    function deviceIsOn(device) {
        return !!(device && device.state && device.state.is_on)
    }

    function deviceTitle(device, fallback) {
        if (device && device.name)
            return device.name
        return fallback || "Device"
    }

    function deviceMeta(device) {
        if (!device)
            return "AVAILABLE"
        var type = typeFor(device).toUpperCase()
        var room = device.room_name ? String(device.room_name).toUpperCase() : "SMART HOME"
        return room + " - " + type
    }

    function lightMeta(device) {
        if (!device)
            return "NEUTRAL 4000K"
        if (hasCapability(device, "color_temperature"))
            return "NEUTRAL 4000K"
        return deviceMeta(device)
    }

    function devicePriority(device) {
        var raw = String((device && ((device.name || "") + " " + (device.entity_id || "") + " " + (device.type || ""))) || "").toLowerCase()
        var type = typeFor(device)
        if (raw.indexOf("tubelight") !== -1 || raw.indexOf("tube") !== -1)
            return 0
        if (type === "light" && raw.indexOf("bulb") !== -1)
            return 1
        if (type === "light")
            return 2
        if (type === "aircon")
            return 3
        if (type === "fan")
            return 4
        if (type === "socket")
            return 5
        if (type === "switch")
            return 6
        if (type === "camera")
            return 7
        return 8
    }

    function sortedRoomDevices(room) {
        var devices = visibleDevices(room)
        var decorated = []
        for (var i = 0; i < devices.length; i++)
            decorated.push({ device: devices[i], rank: devicePriority(devices[i]), active: deviceIsOn(devices[i]) ? 0 : 1, index: i })
        decorated.sort(function(a, b) {
            if (a.rank !== b.rank)
                return a.rank - b.rank
            if (a.active !== b.active)
                return a.active - b.active
            return a.index - b.index
        })
        var out = []
        for (var j = 0; j < decorated.length; j++)
            out.push(decorated[j].device)
        return out
    }

    function statusFor(device) {
        if (!device || !device.state)
            return "READY"
        if (device.state.state === "unknown" || device.state.state === "unavailable")
            return String(device.state.state).toUpperCase()
        if (hasLevel(device) && deviceIsOn(device))
            return levelFor(device) + "%"
        return deviceIsOn(device) ? "ON" : "OFF"
    }

    function hasLevel(device) {
        return !!(device && device.state && (hasCapability(device, "brightness") || hasCapability(device, "percentage") || device.state.brightness !== undefined || device.state.percentage !== undefined))
    }

    function levelFor(device) {
        if (!device || !device.state)
            return 70
        if (device.state.brightness !== undefined && device.state.brightness !== null)
            return Math.max(0, Math.min(100, Math.round(Number(device.state.brightness))))
        if (device.state.percentage !== undefined && device.state.percentage !== null)
            return Math.max(0, Math.min(100, Math.round(Number(device.state.percentage))))
        return deviceIsOn(device) ? 100 : 0
    }

    function commitLevel(device, mouseX, width) {
        if (!device)
            return
        var value = Math.max(0, Math.min(100, Math.round(100 * mouseX / Math.max(1, width))))
        if (hasCapability(device, "brightness") || (device.state && device.state.brightness !== undefined)) {
            deviceSetRequested(device, { brightness: value })
            return
        }
        if (hasCapability(device, "percentage") || (device.state && device.state.percentage !== undefined)) {
            deviceSetRequested(device, { percentage: value })
            return
        }
        deviceActionRequested(device)
    }

    function typeFor(device) {
        var raw = String((device && ((device.type || "") + " " + (device.entity_id || "") + " " + (device.name || ""))) || "").toLowerCase()
        var klass = String(device && device.state && device.state.attributes && device.state.attributes.device_class ? device.state.attributes.device_class : "").toLowerCase()
        if (raw.indexOf("light") !== -1 || raw.indexOf("tube") !== -1 || raw.indexOf("bulb") !== -1 || klass.indexOf("light") !== -1)
            return "light"
        if (raw.indexOf("fan") !== -1)
            return "fan"
        if (raw.indexOf("ac") !== -1 || raw.indexOf("climate") !== -1 || raw.indexOf("air") !== -1)
            return "aircon"
        if (raw.indexOf("plug") !== -1 || raw.indexOf("socket") !== -1 || raw.indexOf("outlet") !== -1)
            return "socket"
        if (raw.indexOf("camera") !== -1)
            return "camera"
        if (raw.indexOf("sensor") !== -1 || klass.length > 0)
            return "sensor"
        return "switch"
    }

    function primaryDevice(room) {
        var devices = sortedRoomDevices(room)
        if (devices.length === 0)
            return null
        return devices[0]
    }

    function secondaryDeviceCards(room, hero) {
        var devices = sortedRoomDevices(room)
        var out = []
        for (var i = 0; i < devices.length && out.length < 4; i++) {
            var d = devices[i]
            if (hero && d.id === hero.id)
                continue
            out.push({
                name: deviceTitle(d, "Socket " + (out.length + 1)),
                meta: deviceMeta(d),
                status: statusFor(d),
                active: deviceIsOn(d),
                raw: d
            })
        }
        var fallback = ["Socket 1", "Socket 2", "Socket 3", "Aircon"]
        var meta = ["DESK", "CHARGER", "LAMP", "1.2KW SOCKET"]
        while (out.length < 4) {
            out.push({
                name: fallback[out.length],
                meta: meta[out.length],
                status: out.length === 0 ? "ON" : "OFF",
                active: out.length === 0,
                raw: null
            })
        }
        return out
    }

    function estimateWatts(device) {
        if (!deviceIsOn(device))
            return 0
        var attrs = device.state && device.state.attributes ? device.state.attributes : {}
        var keys = ["power", "current_power_w", "power_w", "wattage"]
        for (var i = 0; i < keys.length; i++) {
            if (attrs[keys[i]] !== undefined && !isNaN(Number(attrs[keys[i]])))
                return Math.round(Number(attrs[keys[i]]))
        }
        var type = typeFor(device)
        if (type === "light")
            return 18
        if (type === "fan")
            return 45
        if (type === "aircon")
            return 850
        if (type === "socket")
            return 42
        return 12
    }

    function homeLoadWatts() {
        var devices = allDevices()
        var total = 0
        for (var i = 0; i < devices.length; i++)
            total += estimateWatts(devices[i])
        return total > 0 ? total : 142
    }

    function roomLoadWatts(room) {
        var devices = visibleDevices(room)
        var total = 0
        for (var i = 0; i < devices.length; i++)
            total += estimateWatts(devices[i])
        return total > 0 ? total : 96
    }

    function recoveryScore() {
        return health && health.recovery_score ? Math.round(Number(health.recovery_score)) : 84
    }

    function heartRate() {
        return health && health.heart_rate ? Math.round(Number(health.heart_rate)) : 62
    }

    function sleepDuration() {
        return health && health.sleep_duration ? String(health.sleep_duration) : "7:42"
    }

    function weatherLabel() {
        return roomTemperature(selectedRoom()).replace("C", "") + " CLEAR"
    }

    function greetingText() {
        var hour = new Date().getHours()
        var part = hour < 12 ? "morning" : hour < 18 ? "afternoon" : "evening"
        var name = userName && userName.length ? userName : "Ronit"
        return "Good " + part + ", " + name + "."
    }

    function summaryText() {
        var status = healthError ? "backend offline" : realtimeConnected ? "all systems nominal" : "realtime reconnecting"
        return status + " - recovery " + recoveryScore() + " - well rested."
    }

    function healthSyncLabel() {
        if (healthError)
            return "SYSTEM HEALTH - OFFLINE"
        if (health && health.home_assistant && health.home_assistant.ok)
            return "HOME ASSISTANT - ONLINE"
        return "ULTRAHUMAN RING - SYNCED " + clockText
    }

    function dashboardDockModel() {
        var out = []
        var order = preferredRoomIndices()
        var maxRooms = Math.min(2, order.length)
        for (var i = 0; i < maxRooms; i++) {
            var roomIndex = order[i]
            var room = rooms[roomIndex]
            out.push({
                kind: "room",
                index: roomIndex,
                title: roomName(room),
                subtitle: roomSubtitle(room),
                active: activeDeviceCount(visibleDevices(room)) > 0
            })
        }
        while (out.length < 2) {
            out.push({
                kind: "room",
                index: out.length,
                title: out.length === 0 ? "Gaming Room" : "Bedroom",
                subtitle: out.length === 0 ? "TUBELIGHT - 80%" : "21.4C - 2 ON",
                active: true
            })
        }
        out.push({
            kind: "scene",
            title: "Scenes",
            subtitle: sceneSubtitle(),
            active: false
        })
        out.push({
            kind: "health",
            title: "Health",
            subtitle: "RING SYNCED " + clockText,
            active: false
        })
        return out
    }

    function roomSubtitle(room) {
        var devices = visibleDevices(room)
        var hero = primaryDevice(room)
        if (hero)
            return deviceTitle(hero, "DEVICE").toUpperCase() + " - " + statusFor(hero)
        return roomTemperature(room) + " - " + activeDeviceCount(devices) + " ON"
    }

    function sceneSubtitle() {
        if (!scenes || scenes.length === 0)
            return "NIGHT - AWAY - FOCUS"
        var labels = []
        for (var i = 0; i < scenes.length && i < 3; i++)
            labels.push(String(scenes[i].name || "Scene").toUpperCase())
        return labels.join(" - ")
    }

    function handleDockAction(item) {
        if (!item)
            return
        if (item.kind === "room") {
            setRoomIndex(item.index)
            currentScreen = "room"
            return
        }
        if (item.kind === "health") {
            currentScreen = "health"
            return
        }
        if (item.kind === "scene") {
            if (scenes && scenes.length)
                sceneRequested(scenes[0])
            return
        }
    }

    function voicePromptText() {
        if (assistantMessage && assistantMessage !== "waiting for wake-word")
            return assistantMessage
        return "Jarvis, how did I sleep and switch off the bedroom sockets"
    }

    function voiceReplyText() {
        if (assistantStatus === "error" || assistantStatus === "command_error")
            return "I hit a control error. Check the device status and try again."
        if (voicePipelineActive)
            return "Listening for the next command."
        return "You slept " + sleepDuration() + ", recovery " + recoveryScore() + ". Switching off four bedroom sockets."
    }
}
