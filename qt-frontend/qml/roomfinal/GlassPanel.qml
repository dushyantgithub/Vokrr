import QtQuick
import "../components" as VokrrComponents

VokrrComponents.Card {
    id: root

    property var theme
    property bool active: false
    property real radius: theme ? theme.radiusXl : 22
    property real padding: theme ? theme.space6 : 12

    cornerRadius: root.radius
    contentPadding: root.padding
    darkMode: root.theme ? root.theme.darkMode : true
    cardColor: root.theme ? root.theme.bgApp : (darkMode ? "#212121" : "#e8e8e8")
}
