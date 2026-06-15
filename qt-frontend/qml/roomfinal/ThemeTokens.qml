import QtQuick

Item {
    property bool darkMode: true

    readonly property int space1: 2
    readonly property int space2: 4
    readonly property int space3: 6
    readonly property int space4: 8
    readonly property int space5: 10
    readonly property int space6: 12
    readonly property int space8: 16
    readonly property int space10: 20
    readonly property int space12: 24

    readonly property int radiusSm: 10
    readonly property int radiusMd: 16
    readonly property int radiusLg: 22
    readonly property int radiusXl: 28
    readonly property int radiusFull: 999

    readonly property int displaySm: 26
    readonly property int headingMd: 16
    readonly property int bodyMd: 13
    readonly property int bodySm: 12
    readonly property int caption: 10
    readonly property int numberMd: 16
    readonly property int numberLg: 22

    readonly property color bgApp: darkMode ? "#111113" : "#F5F5F7"
    readonly property color bgSurface: darkMode ? "#1C1C1E" : "#FFFFFF"
    readonly property color bgSurfaceSoft: darkMode ? "#242426" : "#ECEEF3"
    readonly property color bgSurfaceGlass: darkMode ? "#D11C1C1E" : "#E8FFFFFF"
    readonly property color bgOverlay: darkMode ? "#8A111113" : "#47FFFFFF"

    readonly property color borderSubtle: darkMode ? "#343437" : "#D9DCE3"
    readonly property color borderActive: darkMode ? "#66FFFFFF" : "#7AFFFFFF"
    readonly property color borderGlow: darkMode ? "#595AC8FA" : "#4764D2FF"

    readonly property color textPrimary: darkMode ? "#F5F5F7" : "#1D1D1F"
    readonly property color textSecondary: darkMode ? "#D1D1D6" : "#3A3A3C"
    readonly property color textMuted: darkMode ? "#A1A1AA" : "#6E6E73"
    readonly property color textDisabled: darkMode ? "#636366" : "#AEAEB2"
    readonly property color textInverse: darkMode ? "#111113" : "#FFFFFF"
    readonly property color iconColor: darkMode ? "#F5F5F7" : "#1D1D1F"

    readonly property color accentBlue: darkMode ? "#64D2FF" : "#007AFF"
    readonly property color accentCyan: darkMode ? "#5AC8FA" : "#0A84FF"
    readonly property color accentCyanSoft: darkMode ? "#7DDCFF" : "#3C8CFF"
    readonly property color accentGreen: darkMode ? "#30D158" : "#34C759"
    readonly property color accentYellow: darkMode ? "#FFD60A" : "#F5B301"
    readonly property color accentOrange: darkMode ? "#FF9F0A" : "#FF9500"
    readonly property color accentRed: darkMode ? "#FF453A" : "#FF3B30"
    readonly property color accentPurple: darkMode ? "#BF5AF2" : "#AF52DE"

    readonly property color cardTop: darkMode ? "#F0222226" : "#F7FFFFFF"
    readonly property color cardBottom: darkMode ? "#DE171719" : "#EDEFF4FA"
    readonly property color activeTop: darkMode ? "#4DFFFFFF" : "#FFFFFFFF"
    readonly property color activeBottom: darkMode ? "#2E5AC8FA" : "#E8FFFFFF"
    readonly property color shadow: darkMode ? "#A8000000" : "#26000000"
    readonly property color appGlow: darkMode ? "#1F5AC8FA" : "#2664D2FF"
    readonly property color pressFill: darkMode ? "#24FFFFFF" : "#1F000000"

    function family() { return "Inter" }

    function accentForType(type, active) {
        var value = String(type).toLowerCase()
        if (!active)
            return textMuted
        if (value === "light")
            return accentYellow
        if (value === "fan" || value === "tv" || value === "curtain")
            return accentBlue
        if (value === "ac" || value === "camera" || value === "speaker" || value === "switch")
            return accentCyan
        if (value === "plug")
            return accentGreen
        if (value === "purifier" || value === "sensor")
            return accentGreen
        return accentCyanSoft
    }
}
