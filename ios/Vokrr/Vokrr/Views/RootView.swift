import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showsNotifications = false

    var body: some View {
        ZStack {
            AuroraBackground()

            switch appState.phase {
            case .booting:
                ProgressView()
                    .tint(Color.white)
            case .login:
                LoginView()
            case .ready:
                content
            }
        }
        .sheet(isPresented: $showsNotifications) {
            NotificationsSheet(notifications: appState.notifications)
        }
        .sheet(item: $appState.selectedDevice) { device in
            DeviceDetailSheet(device: device)
                .environmentObject(appState)
        }
    }

    private var content: some View {
        VStack(spacing: 18) {
            JarvisBar(
                status: appState.jarvisStatus,
                message: appState.jarvisMessage,
                health: appState.health,
                unreadCount: appState.notifications.count,
                onNotifications: { showsNotifications = true }
            )
            .padding(.horizontal, 20)
            .padding(.top, 12)

            if !appState.networkMonitor.isReachable || !appState.bannerMessage.isEmpty {
                Text(appState.networkMonitor.isReachable ? appState.bannerMessage : "No network connection")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.9))
                    .clipShape(Capsule(style: .continuous))
                    .padding(.horizontal, 20)
            }

            ScrollView(showsIndicators: false) {
                Group {
                    switch appState.selectedTab {
                    case .dashboard:
                        DashboardView()
                    case .devices:
                        DevicesView()
                    case .routines:
                        RoutinesView()
                    case .activity:
                        ActivityView()
                    case .news:
                        NewsView()
                    case .settings:
                        SettingsView()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 120)
            }

            BottomTabBar(selectedTab: $appState.selectedTab)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
        }
    }
}
