import SwiftUI

struct ActivityView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader(title: "Activity", subtitle: "Backend, automation, and live session status")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                metricCard(title: "Rooms", value: "\(appState.rooms.count)", tint: QuantumTheme.lavender)
                metricCard(title: "Devices", value: "\(appState.allDevices.count)", tint: QuantumTheme.sky)
                metricCard(title: "Home Assistant", value: (appState.health?.homeAssistant.ok ?? false) ? "Online" : "Offline", tint: (appState.health?.homeAssistant.ok ?? false) ? QuantumTheme.mint : Color.orange)
                metricCard(title: "WebSocket", value: appState.isRealtimeConnected ? "Live" : "Retrying", tint: appState.isRealtimeConnected ? QuantumTheme.mint : Color.orange)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Jarvis")
                    .font(.headline)
                Text(appState.jarvisStatus.capitalized)
                    .font(.title3.bold())
                Text(appState.jarvisMessage)
                    .foregroundStyle(QuantumTheme.secondaryText)
            }
            .padding(20)
            .glassCard()
        }
        .padding(.top, 10)
    }

    private func metricCard(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(QuantumTheme.secondaryText)
            Spacer()
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
        .glassCard(tint: tint)
    }
}
