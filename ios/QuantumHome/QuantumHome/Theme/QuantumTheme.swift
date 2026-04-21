import SwiftUI

enum QuantumTheme {
    static let background = Color(red: 0.03, green: 0.03, blue: 0.05)
    static let panel = Color.white.opacity(0.08)
    static let panelStrong = Color.white.opacity(0.12)
    static let outline = Color.white.opacity(0.10)
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.7)
    static let tertiaryText = Color.white.opacity(0.45)
    static let lavender = Color(red: 0.80, green: 0.70, blue: 1.0)
    static let sky = Color(red: 0.56, green: 0.83, blue: 1.0)
    static let coral = Color(red: 0.98, green: 0.65, blue: 0.61)
    static let mint = Color(red: 0.40, green: 0.86, blue: 0.72)
    static let gradient = LinearGradient(
        colors: [lavender, sky],
        startPoint: .leading,
        endPoint: .trailing
    )
}

struct GlassCardModifier: ViewModifier {
    let tint: Color

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(tint.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
                    )
            )
    }
}

extension View {
    func glassCard(tint: Color = .clear) -> some View {
        modifier(GlassCardModifier(tint: tint))
    }
}
