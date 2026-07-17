import SwiftUI

struct AuroraBackground: View {
    var body: some View {
        VokrrTheme.background.ignoresSafeArea()
    }
}

struct VokrrLogo: View {
    var body: some View {
        Image("VokrrMark")
            .resizable()
            .interpolation(.high)
            .frame(width: 36, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct SectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(VokrrTheme.jost(20))
                .foregroundStyle(VokrrTheme.primaryText)
            Text(subtitle.uppercased())
                .font(VokrrTheme.mono(8))
                .tracking(1.5)
                .foregroundStyle(VokrrTheme.tertiaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TabPill: View {
    let title: String
    let isActive: Bool

    var body: some View {
        Text(title.uppercased())
            .font(VokrrTheme.mono(8, medium: true))
            .tracking(1.5)
            .foregroundStyle(isActive ? VokrrTheme.background : VokrrTheme.secondaryText)
            .padding(.horizontal, 16)
            .frame(height: 36)
            .background(isActive ? VokrrTheme.emerald : VokrrTheme.champagne.opacity(0.06), in: Capsule())
    }
}

struct VokrrConnectionBadge: View {
    let isConnected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isConnected ? VokrrTheme.emerald : VokrrTheme.champagne.opacity(0.35))
                .frame(width: 5, height: 5)
                .shadow(color: isConnected ? VokrrTheme.emerald.opacity(0.9) : .clear, radius: 6)
                .opacity(reduceMotion ? 1 : (breathing ? 0.85 : 0.3))
            Text(isConnected ? "HOME LINKED" : "RECONNECTING")
                .font(VokrrTheme.mono(8, medium: true))
                .tracking(2)
                .foregroundStyle(isConnected ? VokrrTheme.emerald : VokrrTheme.tertiaryText)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background((isConnected ? VokrrTheme.emerald : VokrrTheme.champagne).opacity(0.08), in: Capsule())
        .overlay(Capsule().stroke((isConnected ? VokrrTheme.emerald : VokrrTheme.champagne).opacity(0.30)))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
    }
}

struct VokrrToggle: View {
    let isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? VokrrTheme.emerald : VokrrTheme.champagne.opacity(0.18))
            .frame(width: 42, height: 25)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(VokrrTheme.primaryText)
                    .frame(width: 19, height: 19)
                    .padding(3)
            }
            .animation(VokrrTheme.control, value: isOn)
    }
}

struct VokrrTabBar: View {
    @Binding var selectedTab: VokrrTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            ForEach(VokrrTab.allCases) { tab in
                let isJarvis = tab == .jarvis
                let active = selectedTab == tab
                Button {
                    if reduceMotion {
                        selectedTab = tab
                    } else {
                        withAnimation(VokrrTheme.tab) { selectedTab = tab }
                    }
                } label: {
                    Circle()
                        .fill(background(for: tab, active: active))
                        .frame(width: isJarvis ? 56 : 46, height: isJarvis ? 56 : 46)
                        .overlay(
                            Circle().stroke(border(for: tab, active: active), lineWidth: 1)
                        )
                        .overlay {
                            Image(systemName: icon(for: tab))
                                .font(.system(size: isJarvis ? 21 : 18, weight: .light))
                                .foregroundStyle(foreground(for: tab, active: active))
                        }
                        .shadow(
                            color: active && isJarvis ? VokrrTheme.emerald.opacity(0.45) : .clear,
                            radius: 12
                        )
                }
                .buttonStyle(VokrrPressStyle())
                .accessibilityLabel(tab.rawValue)
                .accessibilityValue(active ? "Selected" : "")
            }
        }
        .padding(8)
        .background(.ultraThinMaterial, in: Capsule())
        .background(Color(red: 13 / 255, green: 16 / 255, blue: 15 / 255).opacity(0.78), in: Capsule())
        .overlay(Capsule().stroke(VokrrTheme.champagne.opacity(0.14)))
        .shadow(color: .black.opacity(0.60), radius: 24, y: 14)
    }

    private func background(for tab: VokrrTab, active: Bool) -> Color {
        if active { return tab == .jarvis ? VokrrTheme.emerald : VokrrTheme.emerald.opacity(0.12) }
        return tab == .jarvis ? VokrrTheme.emerald.opacity(0.14) : .clear
    }

    private func border(for tab: VokrrTab, active: Bool) -> Color {
        if active { return VokrrTheme.emerald.opacity(0.40) }
        return tab == .jarvis ? VokrrTheme.emerald.opacity(0.30) : .clear
    }

    private func foreground(for tab: VokrrTab, active: Bool) -> Color {
        if active { return tab == .jarvis ? VokrrTheme.background : VokrrTheme.emerald }
        return VokrrTheme.secondaryText
    }

    private func icon(for tab: VokrrTab) -> String {
        switch tab {
        case .home: "house"
        case .health: "heart"
        case .jarvis: "mic"
        case .settings: "gearshape"
        }
    }
}

struct VokrrPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.97 : 1))
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct VokrrSplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spinOuter = false
    @State private var spinInner = false
    @State private var pulse = false
    @State private var breathe = false
    @State private var progress = false
    @State private var fading = false

    var body: some View {
        ZStack {
            VokrrTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .stroke(VokrrTheme.emerald.opacity(0.40), style: StrokeStyle(lineWidth: 1, dash: [6, 6]))
                        .rotationEffect(.degrees(spinOuter ? 360 : 0))
                    Circle()
                        .trim(from: 0, to: 0.72)
                        .stroke(VokrrTheme.champagne.opacity(0.38), lineWidth: 1)
                        .padding(15)
                        .rotationEffect(.degrees(spinInner ? -360 : 0))
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [VokrrTheme.emerald.opacity(0.50), VokrrTheme.emerald.opacity(0.06)],
                                center: .center,
                                startRadius: 0,
                                endRadius: 38
                            )
                        )
                        .frame(width: 74, height: 74)
                        .scaleEffect(pulse ? 1.07 : 1)
                        .opacity(pulse ? 1 : 0.85)
                        .shadow(color: VokrrTheme.emerald.opacity(0.35), radius: 20)
                    Text("V")
                        .font(VokrrTheme.jost(34))
                        .tracking(6)
                        .foregroundStyle(VokrrTheme.primaryText)
                }
                .frame(width: 170, height: 170)

                Text("VOKRR")
                    .font(VokrrTheme.jost(26))
                    .tracking(13)
                    .padding(.leading, 13)
                    .foregroundStyle(VokrrTheme.primaryText)
                    .padding(.top, 34)
                Text("GRAND TOURER SERIES")
                    .font(VokrrTheme.mono(7.5))
                    .tracking(4)
                    .foregroundStyle(VokrrTheme.tertiaryText)
                    .opacity(breathe ? 0.85 : 0.30)
                    .padding(.top, 12)
                ZStack(alignment: .leading) {
                    Rectangle().fill(VokrrTheme.champagne.opacity(0.15)).frame(width: 120, height: 1)
                    Rectangle().fill(VokrrTheme.emerald).frame(width: progress ? 120 : 0, height: 1)
                }
                .padding(.top, 30)
            }
        }
        .opacity(fading ? 0 : 1)
        .onAppear {
            guard !reduceMotion else {
                progress = true
                return
            }
            withAnimation(.linear(duration: 14).repeatForever(autoreverses: false)) { spinOuter = true }
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) { spinInner = true }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) { breathe = true }
            withAnimation(.easeOut(duration: 2.4)) { progress = true }
            Task {
                try? await Task.sleep(for: .milliseconds(2_340))
                withAnimation(.easeOut(duration: 0.66)) { fading = true }
            }
        }
        .accessibilityHidden(true)
    }
}
