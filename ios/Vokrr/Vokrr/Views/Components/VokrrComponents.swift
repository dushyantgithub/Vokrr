import SwiftUI

struct AuroraBackground: View {
    var body: some View {
        ZStack {
            VokrrTheme.background
                .ignoresSafeArea()
            Circle()
                .fill(VokrrTheme.lavender.opacity(0.33))
                .frame(width: 280, height: 280)
                .blur(radius: 60)
                .offset(x: 90, y: -240)
            Circle()
                .fill(VokrrTheme.sky.opacity(0.28))
                .frame(width: 260, height: 260)
                .blur(radius: 70)
                .offset(x: -80, y: 80)
            Circle()
                .fill(Color.white.opacity(0.14))
                .frame(width: 180, height: 180)
                .blur(radius: 40)
                .offset(x: -40, y: 180)
        }
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
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(VokrrTheme.secondaryText)
            }
            Spacer()
        }
    }
}

struct TabPill: View {
    let title: String
    let isActive: Bool

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(isActive ? Color.black : Color.white.opacity(0.88))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(isActive ? AnyShapeStyle(VokrrTheme.gradient) : AnyShapeStyle(Color.white.opacity(0.06)))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(isActive ? 0 : 0.08), lineWidth: 1)
            )
    }
}

struct JarvisBar: View {
    let status: String
    let message: String
    let health: HealthResponse?
    let unreadCount: Int
    let onNotifications: () -> Void

    private var statusColor: Color {
        switch status {
        case "listening":
            return VokrrTheme.lavender
        case "processing":
            return VokrrTheme.sky
        case "done":
            return VokrrTheme.mint
        case "error", "command_error":
            return .red.opacity(0.8)
        default:
            return Color.white.opacity(0.8)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 12, height: 12)
                    .shadow(color: statusColor.opacity(0.8), radius: 14)
                VStack(alignment: .leading, spacing: 3) {
                    Text(status.capitalized)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(VokrrTheme.secondaryText)
                    Text(message)
                        .font(.subheadline)
                        .lineLimit(1)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Circle()
                    .fill((health?.homeAssistant.ok ?? false) ? VokrrTheme.mint : Color.orange)
                    .frame(width: 8, height: 8)
                Text((health?.homeAssistant.ok ?? false) ? "Online" : "Offline")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VokrrTheme.secondaryText)
            }

            Button(action: onNotifications) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell")
                        .font(.headline)
                        .foregroundStyle(Color.white)
                    if unreadCount > 0 {
                        Text(unreadCount > 9 ? "9+" : "\(unreadCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.black)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(VokrrTheme.gradient))
                            .offset(x: 12, y: -8)
                    }
                }
                .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .glassCard()
    }
}

struct NotificationsSheet: View {
    let notifications: [NotificationItem]

    var body: some View {
        NavigationStack {
            List(notifications) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Circle()
                            .fill(color(for: item.level))
                            .frame(width: 10, height: 10)
                        Text(item.title)
                            .font(.headline)
                    }
                    Text(item.detail)
                        .font(.subheadline)
                    Text(item.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .background(VokrrTheme.background.ignoresSafeArea())
            .navigationTitle("Notifications")
        }
    }

    private func color(for level: NotificationLevel) -> Color {
        switch level {
        case .info:
            return VokrrTheme.sky
        case .warning:
            return Color.orange
        case .error:
            return Color.red
        }
    }
}

struct BottomTabBar: View {
    @Binding var selectedTab: VokrrTab

    var body: some View {
        HStack {
            ForEach(VokrrTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: icon(for: tab))
                            .font(.headline)
                        Text(label(for: tab))
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(selectedTab == tab ? Color.white : VokrrTheme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 18)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func label(for tab: VokrrTab) -> String {
        switch tab {
        case .dashboard: return "Home"
        default: return tab.rawValue
        }
    }

    private func icon(for tab: VokrrTab) -> String {
        switch tab {
        case .dashboard: return "house.fill"
        case .devices: return "switch.2"
        case .routines: return "sparkles"
        case .activity: return "clock.arrow.circlepath"
        case .news: return "newspaper"
        case .settings: return "gearshape"
        }
    }
}

struct DeviceDetailSheet: View {
    @EnvironmentObject private var appState: AppState
    @State private var sliderValue: Double
    let device: Device

    init(device: Device) {
        self.device = device
        _sliderValue = State(initialValue: device.levelValue)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(device.name)
                            .font(.title.bold())
                        Text(device.roomName)
                            .foregroundStyle(VokrrTheme.secondaryText)
                    }
                    Spacer()
                    Button {
                        Task { await appState.toggleDevice(device) }
                    } label: {
                        Image(systemName: device.state.isOn ? "power.circle.fill" : "power.circle")
                            .font(.system(size: 34))
                            .foregroundStyle(device.state.isOn ? VokrrTheme.lavender : Color.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }

                if device.supportsLevel {
                    VStack(spacing: 20) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 70, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                                .frame(width: 144, height: 360)
                            RoundedRectangle(cornerRadius: 70, style: .continuous)
                                .fill(VokrrTheme.gradient)
                                .frame(width: 144, height: max(40, 320 * sliderValue / 100 + 40))
                            VStack(spacing: 4) {
                                Image(systemName: icon(for: device))
                                    .font(.largeTitle)
                                Text("\(Int(sliderValue))%")
                                    .font(.system(size: 34, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(Color.black.opacity(0.78))
                        }

                        Slider(value: $sliderValue, in: 0 ... 100, step: 1) { editing in
                            if !editing {
                                Task {
                                    await appState.setDevice(device, request: levelRequest(value: Int(sliderValue)))
                                }
                            }
                        }
                        .tint(VokrrTheme.lavender)
                    }
                    .padding(24)
                    .glassCard(tint: VokrrTheme.lavender)
                }

                if device.supportsColorTemperature {
                    HStack(spacing: 12) {
                        temperatureButton(title: "Warm", kelvin: 2700, tint: VokrrTheme.coral)
                        temperatureButton(title: "Neutral", kelvin: 4000, tint: VokrrTheme.lavender)
                        temperatureButton(title: "Cool", kelvin: 6500, tint: VokrrTheme.sky)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Entity")
                        .font(.headline)
                    Text(device.entityID)
                        .font(.footnote.monospaced())
                        .foregroundStyle(VokrrTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .glassCard()
            }
            .padding(20)
        }
        .presentationDetents([.medium, .large])
        .background(VokrrTheme.background.ignoresSafeArea())
    }

    private func temperatureButton(title: String, kelvin: Int, tint: Color) -> some View {
        Button {
            Task {
                await appState.setDevice(device, request: DeviceSetRequest(colorTempKelvin: kelvin))
            }
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(tint)
                    .frame(width: 10, height: 10)
                Text(title)
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .glassCard(tint: tint)
        }
        .buttonStyle(.plain)
    }

    private func levelRequest(value: Int) -> DeviceSetRequest {
        if device.capabilities.contains(.brightness) {
            return DeviceSetRequest(brightness: value)
        }
        return DeviceSetRequest(percentage: value)
    }

    private func icon(for device: Device) -> String {
        switch device.type {
        case .light: return "lightbulb.fill"
        case .fan: return "fan.fill"
        case .switch: return "switch.2"
        case .sensor: return "sensor"
        case .scene: return "sparkles"
        case .unknown: return "switch.2"
        }
    }
}
