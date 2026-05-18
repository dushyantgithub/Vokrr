import QtQuick
import QtQuick.Controls

ApplicationWindow {
    id: window

    width: 800
    height: 480
    visible: true
    color: "#212121"
    title: "Radar Effect Demo"

    RadarDemoContent {
        anchors.fill: parent
    }
}
