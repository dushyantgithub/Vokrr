import SwiftUI

enum VokrrTheme {
    static let background = Color(red: 6 / 255, green: 8 / 255, blue: 7 / 255)
    static let surface = Color(red: 11 / 255, green: 14 / 255, blue: 13 / 255)
    static let primaryText = Color(red: 238 / 255, green: 242 / 255, blue: 239 / 255)
    static let secondaryText = Color(red: 138 / 255, green: 150 / 255, blue: 145 / 255)
    static let tertiaryText = Color(red: 95 / 255, green: 107 / 255, blue: 102 / 255)
    static let emerald = Color(red: 46 / 255, green: 199 / 255, blue: 154 / 255)
    static let emeraldLight = Color(red: 127 / 255, green: 233 / 255, blue: 198 / 255)
    static let champagne = Color(red: 217 / 255, green: 203 / 255, blue: 168 / 255)
    static let sleepBlue = Color(red: 127 / 255, green: 176 / 255, blue: 201 / 255)

    // Compatibility aliases retained for the secondary admin flows.
    static let panel = champagne.opacity(0.05)
    static let panelStrong = champagne.opacity(0.10)
    static let outline = champagne.opacity(0.12)
    static let lavender = emerald
    static let sky = sleepBlue
    static let coral = champagne
    static let mint = emeraldLight
    static let gradient = LinearGradient(colors: [emerald, emeraldLight], startPoint: .leading, endPoint: .trailing)

    static func jost(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Jost-Regular", size: size).weight(weight)
    }

    static func mono(_ size: CGFloat, medium: Bool = false) -> Font {
        .custom(medium ? "IBMPlexMono-Medium" : "IBMPlexMono-Regular", size: size)
    }

    static let entrance = Animation.timingCurve(0.22, 0.9, 0.32, 1, duration: 0.45)
    static let roomEntrance = Animation.easeOut(duration: 0.35)
    static let control = Animation.easeInOut(duration: 0.25)
    static let tab = Animation.easeInOut(duration: 0.30)
}

struct GlassCardModifier: ViewModifier {
    let tint: Color
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(VokrrTheme.champagne.opacity(0.045))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(tint.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(VokrrTheme.champagne.opacity(0.12), lineWidth: 1)
                    )
            )
    }
}

extension View {
    func glassCard(tint: Color = .clear, cornerRadius: CGFloat = 26) -> some View {
        modifier(GlassCardModifier(tint: tint, cornerRadius: cornerRadius))
    }

    func vokrrEntrance(active: Bool, reduceMotion: Bool) -> some View {
        opacity(active ? 1 : 0)
            .offset(y: reduceMotion ? 0 : (active ? 0 : 16))
            .animation(reduceMotion ? nil : VokrrTheme.entrance, value: active)
    }
}
