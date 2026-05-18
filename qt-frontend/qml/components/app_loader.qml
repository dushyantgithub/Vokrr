import QtQuick

Item {
    id: root

    width: size
    height: size

    property int size: 200
    property color trackColor: "#71717a"
    property color loaderColor: "#4FA593"
    property real trackOpacity: 0.5
    property int duration: 2000
    property bool running: true
    property real progress: 0

    function mapX(v) { return (v + 2) * width / 44 }
    function mapY(v) { return (v + 2) * height / 44 }

    function cubic(p0, p1, p2, p3, t) {
        var mt = 1 - t
        return {
            x: mt * mt * mt * p0.x + 3 * mt * mt * t * p1.x + 3 * mt * t * t * p2.x + t * t * t * p3.x,
            y: mt * mt * mt * p0.y + 3 * mt * mt * t * p1.y + 3 * mt * t * t * p2.y + t * t * t * p3.y
        }
    }

    function buildPath() {
        var p = []
        var current = { x: 29.76, y: 18.72 }
        p.push(current)

        function add(c1x, c1y, c2x, c2y, x, y) {
            var c1 = { x: c1x, y: c1y }
            var c2 = { x: c2x, y: c2y }
            var next = { x: x, y: y }
            for (var i = 1; i <= 18; i++)
                p.push(cubic(current, c1, c2, next, i / 18))
            current = next
        }

        add(29.76, 26.00, 25.84, 32.32, 19.92, 35.68)
        add(17.04, 37.36, 13.68, 38.32, 10.08, 38.32)
        add(6.48, 38.32, 3.20, 37.36, 0.32, 35.68)
        add(0.32, 28.40, 4.24, 22.16, 10.16, 18.72)
        add(13.04, 17.04, 16.40, 16.08, 19.92, 16.08)
        add(23.44, 16.08, 26.88, 17.04, 29.76, 18.72)
        add(35.60, 22.08, 39.52, 28.40, 39.60, 35.68)
        add(36.72, 37.36, 33.36, 38.32, 29.84, 38.32)
        add(26.24, 38.32, 22.96, 37.36, 20.00, 35.68)
        add(14.16, 32.32, 10.24, 26.00, 10.24, 18.72)
        add(10.24, 11.44, 14.16, 5.12, 20.00, 1.76)
        add(25.84, 5.12, 29.76, 11.44, 29.76, 18.72)
        return p
    }

    function drawPolyline(ctx, points, fromDistance, toDistance) {
        var distance = 0
        var drawing = false

        for (var i = 1; i < points.length; i++) {
            var a = points[i - 1]
            var b = points[i]
            var len = Math.sqrt(Math.pow(b.x - a.x, 2) + Math.pow(b.y - a.y, 2))
            var segStart = distance
            var segEnd = distance + len

            if (segEnd >= fromDistance && segStart <= toDistance) {
                var startT = Math.max(0, (fromDistance - segStart) / len)
                var endT = Math.min(1, (toDistance - segStart) / len)
                var sx = a.x + (b.x - a.x) * startT
                var sy = a.y + (b.y - a.y) * startT
                var ex = a.x + (b.x - a.x) * endT
                var ey = a.y + (b.y - a.y) * endT

                if (!drawing) {
                    ctx.moveTo(mapX(sx), mapY(sy))
                    drawing = true
                }
                ctx.lineTo(mapX(ex), mapY(ey))
            }

            distance = segEnd
        }
    }

    Canvas {
        id: canvas
        anchors.fill: parent

        onPaint: {
            var ctx = getContext("2d")
            var points = buildPath()
            var total = 0

            ctx.clearRect(0, 0, width, height)
            ctx.lineCap = "round"
            ctx.lineJoin = "round"
            ctx.lineWidth = Math.max(2, width * 4 / 44)

            for (var i = 1; i < points.length; i++)
                total += Math.sqrt(Math.pow(points[i].x - points[i - 1].x, 2) + Math.pow(points[i].y - points[i - 1].y, 2))

            ctx.globalAlpha = root.trackOpacity
            ctx.strokeStyle = root.trackColor
            ctx.beginPath()
            ctx.moveTo(mapX(points[0].x), mapY(points[0].y))
            for (var t = 1; t < points.length; t++)
                ctx.lineTo(mapX(points[t].x), mapY(points[t].y))
            ctx.stroke()

            ctx.globalAlpha = 1
            ctx.strokeStyle = root.loaderColor
            ctx.beginPath()

            var segment = total * 0.15
            var start = (root.progress * total) % total
            var end = start + segment

            drawPolyline(ctx, points, start, Math.min(end, total))
            if (end > total)
                drawPolyline(ctx, points, 0, end - total)

            ctx.stroke()
        }
    }

    NumberAnimation on progress {
        from: 0
        to: 1
        duration: root.duration
        loops: Animation.Infinite
        running: root.running
    }

    Connections {
        target: root
        function onProgressChanged() { canvas.requestPaint() }
        function onWidthChanged() { canvas.requestPaint() }
        function onHeightChanged() { canvas.requestPaint() }
        function onTrackColorChanged() { canvas.requestPaint() }
        function onLoaderColorChanged() { canvas.requestPaint() }
        function onTrackOpacityChanged() { canvas.requestPaint() }
    }
}
