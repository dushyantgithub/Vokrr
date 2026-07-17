import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsSplash = !ProcessInfo.processInfo.arguments.contains("-VOKRRSkipSplash")

    var body: some View {
        ZStack {
            VokrrTheme.background.ignoresSafeArea()

            switch appState.phase {
            case .booting:
                Color.clear
            case .login:
                LoginView()
            case .ready:
                readyContent
            }

            if showsSplash {
                VokrrSplashView()
                    .zIndex(100)
            }
        }
        .foregroundStyle(VokrrTheme.primaryText)
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $appState.isDeviceOnboardingPresented) {
            DeviceOnboardingFlow()
                .environmentObject(appState)
        }
        .task {
            if reduceMotion {
                try? await Task.sleep(for: .milliseconds(350))
            } else {
                try? await Task.sleep(for: .milliseconds(3_050))
            }
            showsSplash = false
        }
        .onOpenURL { url in
            guard url.scheme == "vokrr" else { return }
            switch url.host {
            case "health": appState.selectedTab = .health
            case "jarvis": appState.selectedTab = .jarvis
            case "settings": appState.selectedTab = .settings
            default: appState.selectedTab = .home
            }
        }
    }

    private var readyContent: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch appState.selectedTab {
                case .home:
                    DashboardView()
                case .health:
                    HealthView()
                case .jarvis:
                    JarvisView()
                case .settings:
                    SettingsView()
                }
            }
            .id(appState.selectedTab)
            .transition(
                reduceMotion
                    ? .opacity
                    : .asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 16)),
                        removal: .opacity
                    )
            )
            .animation(reduceMotion ? nil : VokrrTheme.entrance, value: appState.selectedTab)

            VokrrTabBar(selectedTab: $appState.selectedTab)
                .padding(.bottom, 12)
                .zIndex(20)

            if !appState.networkMonitor.isReachable || !appState.bannerMessage.isEmpty {
                Text(appState.networkMonitor.isReachable ? appState.bannerMessage : "NO NETWORK CONNECTION")
                    .font(VokrrTheme.mono(8, medium: true))
                    .tracking(1.2)
                    .foregroundStyle(VokrrTheme.background)
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .background(VokrrTheme.champagne, in: Capsule())
                    .padding(.bottom, 94)
                    .onTapGesture { appState.bannerMessage = "" }
                    .zIndex(30)
            }
        }
        .ignoresSafeArea(.keyboard)
    }
}
