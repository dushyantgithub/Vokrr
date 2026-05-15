import QtQuick

Item {
    id: root

    width: 800
    height: 400

    property string centerText: "VOKRR"
    property bool showCpuConnections: true
    property bool animateText: true
    property bool animateLines: true
    property bool animateMarkers: true
    property real lineProgress: 0
    property real pulse: 0
    property real textPhase: 0

    signal navigationRequested(string panelName)
    signal restartRequested()

    function sx(v) { return v * width / 200 }
    function sy(v) { return v * height / 100 }
    function pt(x, y) { return { x: x, y: y } }

    function dist(a, b) {
        return Math.sqrt(Math.pow(b.x - a.x, 2) + Math.pow(b.y - a.y, 2))
    }

    function lerp(a, b, t) {
        return pt(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)
    }

    function quad(p0, p1, p2, t) {
        var mt = 1 - t
        return pt(
            mt * mt * p0.x + 2 * mt * t * p1.x + t * t * p2.x,
            mt * mt * p0.y + 2 * mt * t * p1.y + t * t * p2.y
        )
    }

    function addLine(points, x, y) {
        points.push(pt(x, y))
    }

    function addQuad(points, cx, cy, x, y) {
        var start = points[points.length - 1]
        var control = pt(cx, cy)
        var end = pt(x, y)
        for (var i = 1; i <= 10; i++)
            points.push(quad(start, control, end, i / 10))
    }

    function makePaths() {
        var p = []
        var a

        a = [pt(10, 20)]
        addLine(a, 89.25, 20); addQuad(a, 94.25, 20, 94.25, 25); addLine(a, 94.25, 60.5)
        p.push(a)

        a = [pt(180, 10)]
        addLine(a, 110.25, 10); addQuad(a, 105.25, 10, 105.25, 15); addLine(a, 105.25, 39.5)
        p.push(a)

        a = [pt(130, 20)]
        addLine(a, 130, 43.25); addQuad(a, 130, 48.25, 125, 48.25); addLine(a, 117.5, 48.25)
        p.push(a)

        a = [pt(170, 80)]
        addLine(a, 170, 59.25); addQuad(a, 170, 54.25, 165, 54.25); addLine(a, 117.5, 54.25)
        p.push(a)

        a = [pt(135, 65)]
        addLine(a, 150, 65); addQuad(a, 155, 65, 155, 70); addLine(a, 155, 80); addQuad(a, 155, 85, 150, 85)
        addLine(a, 110.25, 85); addQuad(a, 105.25, 85, 105.25, 80); addLine(a, 105.25, 60.5)
        p.push(a)

        a = [pt(94.8, 95)]
        addLine(a, 94.25, 60.5)
        p.push(a)

        a = [pt(88, 88)]
        addLine(a, 88, 73); addQuad(a, 88, 68, 83, 68); addLine(a, 73, 68); addQuad(a, 68, 68, 68, 63)
        addLine(a, 68, 59.25); addQuad(a, 68, 54.25, 73, 54.25); addLine(a, 82.5, 54.25)
        p.push(a)

        a = [pt(30, 30)]
        addLine(a, 55, 30); addQuad(a, 60, 30, 60, 35); addLine(a, 60, 43.25); addQuad(a, 60, 48.25, 65, 48.25)
        addLine(a, 82.5, 48.25)
        p.push(a)

        return p
    }

    function pathLength(points) {
        var length = 0
        for (var i = 1; i < points.length; i++)
            length += dist(points[i - 1], points[i])
        return length
    }

    function pointAt(points, amount) {
        var target = pathLength(points) * Math.max(0, Math.min(1, amount))
        var walked = 0
        for (var i = 1; i < points.length; i++) {
            var segment = dist(points[i - 1], points[i])
            if (walked + segment >= target)
                return lerp(points[i - 1], points[i], (target - walked) / segment)
            walked += segment
        }
        return points[points.length - 1]
    }

    function drawPathSegment(ctx, points, from, to) {
        var total = pathLength(points)
        var start = total * from
        var end = total * to
        var walked = 0
        var drawing = false

        for (var i = 1; i < points.length; i++) {
            var a = points[i - 1]
            var b = points[i]
            var length = dist(a, b)
            var segmentStart = walked
            var segmentEnd = walked + length

            if (segmentEnd >= start && segmentStart <= end) {
                var t1 = Math.max(0, (start - segmentStart) / length)
                var t2 = Math.min(1, (end - segmentStart) / length)
                var p1 = lerp(a, b, t1)
                var p2 = lerp(a, b, t2)

                if (!drawing) {
                    ctx.moveTo(sx(p1.x), sy(p1.y))
                    drawing = true
                }
                ctx.lineTo(sx(p2.x), sy(p2.y))
            }

            walked = segmentEnd
        }
    }

    function roundedRect(ctx, x, y, w, h, r) {
        var radius = Math.min(r, w / 2, h / 2)
        ctx.moveTo(x + radius, y)
        ctx.lineTo(x + w - radius, y)
        ctx.quadraticCurveTo(x + w, y, x + w, y + radius)
        ctx.lineTo(x + w, y + h - radius)
        ctx.quadraticCurveTo(x + w, y + h, x + w - radius, y + h)
        ctx.lineTo(x + radius, y + h)
        ctx.quadraticCurveTo(x, y + h, x, y + h - radius)
        ctx.lineTo(x, y + radius)
        ctx.quadraticCurveTo(x, y, x + radius, y)
    }

    Canvas {
        id: canvas
        anchors.fill: parent

        onPaint: {
            var ctx = getContext("2d")
            var paths = makePaths()
            var markers = [[135, 65], [94.8, 95], [88, 88], [30, 30]]
            var colors = ["#00E8ED", "#FFD800", "#FF008B", "#ffffff", "#22c55e", "#f97316", "#06b6d4", "#f43f5e"]

            ctx.clearRect(0, 0, width, height)
            ctx.lineCap = "round"
            ctx.lineJoin = "round"

            ctx.save()
            ctx.strokeStyle = "#737373"
            ctx.globalAlpha = 0.9
            ctx.lineWidth = Math.max(1, width * 0.0015)

            for (var i = 0; i < paths.length; i++) {
                ctx.beginPath()
                drawPathSegment(ctx, paths[i], 0, animateLines ? lineProgress : 1)
                ctx.stroke()
            }
            ctx.restore()

            if (animateMarkers) {
                for (var g = 0; g < paths.length; g++) {
                    ctx.save()
                    ctx.strokeStyle = colors[g]
                    ctx.globalAlpha = 0.16
                    ctx.lineWidth = Math.max(3, width * 0.006)
                    ctx.beginPath()
                    drawPathSegment(ctx, paths[g], Math.max(0, pulse - 0.11), pulse)
                    ctx.stroke()
                    ctx.restore()

                    ctx.save()
                    ctx.strokeStyle = colors[g]
                    ctx.globalAlpha = 0.7
                    ctx.lineWidth = Math.max(2, width * 0.0032)
                    ctx.beginPath()
                    drawPathSegment(ctx, paths[g], Math.max(0, pulse - 0.11), pulse)
                    ctx.stroke()
                    ctx.restore()
                }
            }

            for (var m = 0; m < markers.length; m++) {
                ctx.beginPath()
                ctx.fillStyle = "#050505"
                ctx.strokeStyle = "#232323"
                ctx.lineWidth = Math.max(1, width * 0.0006)
                ctx.arc(sx(markers[m][0]), sy(markers[m][1]), sx(2), 0, Math.PI * 2)
                ctx.fill()
                ctx.stroke()
            }

            if (showCpuConnections) {
                ctx.fillStyle = "#151515"

                function pin(x, y, w, h) {
                    ctx.beginPath()
                    roundedRect(ctx, sx(x), sy(y), sx(w), sy(h), Math.max(1, sx(0.7)))
                    ctx.fill()
                }

                pin(93, 37, 2.5, 5)
                pin(104, 37, 2.5, 5)
                pin(93, 58, 2.5, 5)
                pin(104, 58, 2.5, 5)
                pin(80, 47, 5, 2.5)
                pin(80, 53, 5, 2.5)
                pin(115, 47, 5, 2.5)
                pin(115, 53, 5, 2.5)
            }

            ctx.fillStyle = "rgba(0,0,0,0.10)"
            ctx.beginPath()
            roundedRect(ctx, sx(86.2), sy(40.7), sx(30), sy(20), sx(2))
            ctx.fill()

            ctx.fillStyle = "#101010"
            ctx.beginPath()
            roundedRect(ctx, sx(85), sy(40), sx(30), sy(20), sx(2))
            ctx.fill()

            var fontSize = Math.min(sx(6.3), sy(7.2))
            ctx.font = "600 " + fontSize + "px sans-serif"
            ctx.textBaseline = "middle"
            ctx.textAlign = "center"

            if (animateText) {
                var startX = sx(90 + textPhase * 18)
                var textGradient = ctx.createLinearGradient(startX - sx(12), 0, startX + sx(12), 0)
                textGradient.addColorStop(0, "#666666")
                textGradient.addColorStop(0.5, "#ffffff")
                textGradient.addColorStop(1, "#666666")
                ctx.fillStyle = textGradient
            } else {
                ctx.fillStyle = "#ffffff"
            }

            ctx.fillText(centerText, sx(100), sy(50.5))
        }
    }

    CpuEndpointButton {
        nodeX: 10
        nodeY: 20
        iconName: "network"
        onClicked: root.navigationRequested("Network")
    }

    CpuEndpointButton {
        nodeX: 180
        nodeY: 10
        iconName: "profile"
        onClicked: root.navigationRequested("Profile")
    }

    CpuEndpointButton {
        nodeX: 130
        nodeY: 20
        iconName: "information"
        onClicked: root.navigationRequested("Information")
    }

    CpuEndpointButton {
        nodeX: 170
        nodeY: 80
        iconName: "restart"
        onClicked: root.restartRequested()
    }

    NumberAnimation on lineProgress {
        from: 0
        to: 1
        duration: 1000
        running: root.visible
        easing.type: Easing.OutCubic
    }

    SequentialAnimation on pulse {
        running: root.visible
        loops: Animation.Infinite

        NumberAnimation {
            from: 0
            to: 1
            duration: 5200
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1
            to: 0
            duration: 5200
            easing.type: Easing.InOutSine
        }
    }

    SequentialAnimation on textPhase {
        running: root.visible && root.animateText
        loops: Animation.Infinite

        NumberAnimation {
            from: -1
            to: 1
            duration: 5000
            easing.type: Easing.InOutCubic
        }
    }

    Connections {
        target: root
        function onLineProgressChanged() { canvas.requestPaint() }
        function onPulseChanged() { canvas.requestPaint() }
        function onTextPhaseChanged() { canvas.requestPaint() }
        function onWidthChanged() { canvas.requestPaint() }
        function onHeightChanged() { canvas.requestPaint() }
        function onCenterTextChanged() { canvas.requestPaint() }
        function onShowCpuConnectionsChanged() { canvas.requestPaint() }
    }

    component CpuEndpointButton: Button {
        id: endpointButton

        property real nodeX: 0
        property real nodeY: 0
        property string iconName: ""

        width: Math.max(44, Math.min(root.width, root.height) * 0.12)
        height: width
        x: root.sx(nodeX) - width / 2
        y: root.sy(nodeY) - height / 2
        variant: "shadow"

        contentItem: Component {
            Canvas {
                width: Math.max(20, endpointButton.width * 0.44)
                height: width

                onPaint: {
                    var ctx = getContext("2d")
                    var s = width / 24

                    ctx.clearRect(0, 0, width, height)
                    ctx.save()
                    ctx.scale(s, s)
                    ctx.strokeStyle = "#d7fffb"
                    ctx.fillStyle = "#d7fffb"
                    ctx.lineWidth = 2
                    ctx.lineCap = "round"
                    ctx.lineJoin = "round"

                    if (endpointButton.iconName === "network") {
                        ctx.beginPath()
                        ctx.moveTo(16.73, 13.39)
                        ctx.bezierCurveTo(14.11, 10.77, 9.88, 10.76, 7.27, 13.36)
                        ctx.stroke()

                        ctx.beginPath()
                        ctx.moveTo(20.69, 9.44)
                        ctx.bezierCurveTo(15.89, 4.67, 8.11, 4.67, 3.31, 9.44)
                        ctx.stroke()

                        ctx.beginPath()
                        ctx.arc(12, 18, 1, 0, Math.PI * 2)
                        ctx.stroke()
                    } else if (endpointButton.iconName === "profile") {
                        ctx.beginPath()
                        ctx.arc(12, 7.5, 4.5, 0, Math.PI * 2)
                        ctx.fill()

                        ctx.beginPath()
                        ctx.moveTo(4.5, 21)
                        ctx.bezierCurveTo(4.5, 21, 3, 21, 3, 19.5)
                        ctx.bezierCurveTo(3, 18, 4.5, 13.5, 12, 13.5)
                        ctx.bezierCurveTo(19.5, 13.5, 21, 18, 21, 19.5)
                        ctx.bezierCurveTo(21, 21, 19.5, 21, 19.5, 21)
                        ctx.closePath()
                        ctx.fill()
                    } else if (endpointButton.iconName === "information") {
                        ctx.beginPath()
                        ctx.arc(12, 12, 9, 0, Math.PI * 2)
                        ctx.stroke()

                        ctx.beginPath()
                        ctx.moveTo(12, 8)
                        ctx.lineTo(12, 8.5)
                        ctx.moveTo(12, 12)
                        ctx.lineTo(12, 16)
                        ctx.stroke()
                    } else if (endpointButton.iconName === "restart") {
                        ctx.beginPath()
                        ctx.moveTo(12, 4)
                        ctx.lineTo(12, 12)
                        ctx.stroke()

                        ctx.beginPath()
                        ctx.moveTo(17.29, 6)
                        ctx.bezierCurveTo(18.95, 7.47, 20, 9.61, 20, 12)
                        ctx.bezierCurveTo(20, 16.42, 16.42, 20, 12, 20)
                        ctx.bezierCurveTo(7.58, 20, 4, 16.42, 4, 12)
                        ctx.bezierCurveTo(4, 9.61, 5.05, 7.47, 6.71, 6)
                        ctx.stroke()
                    }

                    ctx.restore()
                }
            }
        }
    }
}
