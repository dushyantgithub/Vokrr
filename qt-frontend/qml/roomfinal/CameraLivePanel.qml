import QtQuick
import QtMultimedia

GlassPanel {
    id: root

    property var cameras: []
    readonly property bool hasCameraEntity: cameras && cameras.length > 0
    property var selectedFormat: null

    width: 184
    height: 166
    radius: theme.radiusXl - 2
    padding: theme.space5

    function cameraName() {
        return hasCameraEntity ? (cameras[0].name || "Camera") : "Camera"
    }

    MediaDevices {
        id: mediaDevices
        onVideoInputsChanged: root.refreshFormat()
    }

    function bestFormat(device) {
        if (!device || !device.videoFormats || device.videoFormats.length === 0)
            return null

        var best = null
        var bestScore = -1000000
        for (var i = 0; i < device.videoFormats.length; i++) {
            var format = device.videoFormats[i]
            if (!format || !format.resolution)
                continue

            var formatWidth = format.resolution.width
            var formatHeight = format.resolution.height
            var fps = format.maxFrameRate || 0
            var pixels = formatWidth * formatHeight
            var score = -Math.abs(pixels - 307200) / 1000 + fps * 10

            if (formatWidth === 640 && formatHeight === 480)
                score += 10000
            if (fps >= 30)
                score += 500

            if (score > bestScore) {
                bestScore = score
                best = format
            }
        }
        return best
    }

    function refreshFormat() {
        selectedFormat = bestFormat(camera.cameraDevice)
    }

    CaptureSession {
        camera: Camera {
            id: camera
            active: root.visible && mediaDevices.videoInputs.length > 0
            cameraDevice: mediaDevices.defaultVideoInput
            cameraFormat: root.selectedFormat

            Component.onCompleted: root.refreshFormat()
            onCameraDeviceChanged: root.refreshFormat()
        }
        videoOutput: videoOutput
    }

    Text {
        x: 0
        y: 0
        width: parent.width - 44
        text: root.cameraName()
        color: theme.textPrimary
        font.family: theme.family()
        font.pixelSize: theme.bodyMd
        font.bold: true
        elide: Text.ElideRight
    }

    Row {
        anchors.right: parent.right
        y: 1
        spacing: theme.space2
        Rectangle {
            width: 7
            height: 7
            radius: theme.radiusFull
            color: camera.active ? theme.accentRed : theme.textDisabled
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            text: camera.active ? "Live" : "Idle"
            color: camera.active ? theme.accentRed : theme.textMuted
            font.family: theme.family()
            font.pixelSize: theme.caption
            font.bold: true
        }
    }

    Rectangle {
        x: 0
        y: 28
        width: parent.width
        height: parent.height - 28
        radius: theme.radiusMd
        color: theme.bgSurfaceSoft
        border.width: 0
        clip: true

        VideoOutput {
            id: videoOutput
            anchors.fill: parent
            fillMode: VideoOutput.PreserveAspectCrop
            visible: camera.active
        }

        Column {
            anchors.centerIn: parent
            spacing: theme.space4
            visible: !camera.active
            SvgIcon {
                width: 26
                height: 26
                anchors.horizontalCenter: parent.horizontalCenter
                name: "camera"
                iconColor: theme.iconColor
                darkMode: theme.darkMode
            }
            Text {
                width: 132
                text: mediaDevices.videoInputs.length > 0 ? "Camera feed unavailable" : "No camera input"
                color: theme.textMuted
                font.family: theme.family()
                font.pixelSize: theme.bodySm
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
        }
    }
}
