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
    readonly property int radiusMd: 14
    readonly property int radiusLg: 18
    readonly property int radiusXl: 22
    readonly property int radiusFull: 999

    readonly property int displaySm: 26
    readonly property int headingMd: 16
    readonly property int bodyMd: 13
    readonly property int bodySm: 12
    readonly property int caption: 10
    readonly property int numberMd: 16
    readonly property int numberLg: 22

    readonly property color bgApp: darkMode ? "#212121" : "#e8e8e8"
    readonly property color bgSurface: darkMode ? "#0B1220" : "#FFFFFF"
    readonly property color bgSurfaceSoft: darkMode ? "#101827" : "#F1F7FF"
    readonly property color bgSurfaceGlass: darkMode ? "#B80A1220" : "#BFFFFFFF"
    readonly property color bgOverlay: darkMode ? "#75030712" : "#4DFFFFFF"

    readonly property color borderSubtle: darkMode ? "#2494A3B8" : "#1A0F172A"
    readonly property color borderActive: darkMode ? "#6B2D7DFF" : "#611E6BFF"
    readonly property color borderGlow: darkMode ? "#5900AEEF" : "#47009EE2"

    readonly property color textPrimary: darkMode ? "#e8e8e8" : "#212121"
    readonly property color textSecondary: darkMode ? "#CBD5E1" : "#334155"
    readonly property color textMuted: darkMode ? "#94A3B8" : "#64748B"
    readonly property color textDisabled: darkMode ? "#64748B" : "#94A3B8"
    readonly property color textInverse: darkMode ? "#020617" : "#FFFFFF"
    readonly property color iconColor: darkMode ? "#e8e8e8" : "#212121"

    readonly property color accentBlue: darkMode ? "#2D7DFF" : "#1E6BFF"
    readonly property color accentCyan: darkMode ? "#00AEEF" : "#009EE2"
    readonly property color accentCyanSoft: darkMode ? "#38BDF8" : "#0284C7"
    readonly property color accentGreen: darkMode ? "#00D26A" : "#00A85A"
    readonly property color accentYellow: darkMode ? "#FBBF24" : "#EAB308"
    readonly property color accentOrange: darkMode ? "#F59E0B" : "#EA8A00"
    readonly property color accentRed: darkMode ? "#FF3B30" : "#E53935"
    readonly property color accentPurple: darkMode ? "#8B5CF6" : "#7C3AED"

    readonly property color cardTop: darkMode ? "#EA0F172A" : "#F0FFFFFF"
    readonly property color cardBottom: darkMode ? "#C7020617" : "#D1F1F7FF"
    readonly property color activeTop: darkMode ? "#572D7DFF" : "#2E2D7DFF"
    readonly property color activeBottom: darkMode ? "#1F00AEEF" : "#1A00AEEF"
    readonly property color shadow: darkMode ? "#57000000" : "#1A0F172A"
    readonly property color appGlow: darkMode ? "#2400AEEF" : "#2E00AEEF"
    readonly property color pressFill: darkMode ? "#1FFFFFFF" : "#1A1E6BFF"

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
        if (value === "purifier" || value === "sensor")
            return accentGreen
        return accentCyanSoft
    }
}
