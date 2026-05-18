import QtQuick

Item {
    id: root

    property string name: "activity"
    property color iconColor: "white"
    property bool darkMode: false

    function sourcePath() {
        return "qrc:/assets/icons/" + (darkMode ? "lucide-white/" : "lucide/") + name + ".svg"
    }

    Image {
        id: iconImage
        anchors.fill: parent
        source: root.sourcePath()
        fillMode: Image.PreserveAspectFit
        mipmap: true
        smooth: true
    }
}
