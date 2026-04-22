import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            hero

            SectionHeader(title: "Favourites", subtitle: "Fast access to the most-used devices")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 2), spacing: 14) {
                ForEach(appState.favoriteDevices) { device in
                    DeviceTile(device: device, emphasis: tileTint(for: device)) {
                        appState.selectedDevice = device
                    } onToggle: {
                        Task { await appState.toggleDevice(device) }
                    }
                }
            }

            suggestionCard

            HStack {
                SectionHeader(title: "Rooms", subtitle: "Toggle the room state without adding or removing devices")
                Spacer()
                Button("See all") {
                    appState.selectedTab = .devices
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(VokrrTheme.secondaryText)
            }

            ForEach(appState.rooms) { room in
                RoomSummaryCard(room: room) { isOn in
                    Task { await appState.setRoomState(room, isOn: isOn) }
                }
            }
        }
        .padding(.top, 10)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Good evening")
                        .font(.headline.weight(.medium))
                        .foregroundStyle(VokrrTheme.secondaryText)
                    Text("Vokrr")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                }
                Spacer()
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                    Circle()
                        .fill(VokrrTheme.gradient)
                        .frame(width: 34, height: 34)
                        .overlay(Text("Q").font(.subheadline.weight(.bold)).foregroundStyle(Color.black))
                }
                .foregroundStyle(Color.white)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(appState.scenes) { scene in
                        Button(scene.name) {
                            Task { await appState.runScene(scene) }
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.07))
                        .clipShape(Capsule(style: .continuous))
                    }
                }
            }
        }
        .padding(22)
        .glassCard()
    }

    private var suggestionCard: some View {
        let nextDevice = appState.allDevices.first(where: { !$0.state.isOn }) ?? appState.allDevices.first
        return HStack(spacing: 14) {
            Circle()
                .fill(VokrrTheme.lavender.opacity(0.25))
                .frame(width: 54, height: 54)
                .overlay(Image(systemName: "sun.max.fill").foregroundStyle(VokrrTheme.lavender))
            VStack(alignment: .leading, spacing: 5) {
                Text("Suggested for now")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VokrrTheme.secondaryText)
                Text(nextDevice.map { "Turn on \($0.name) in \($0.roomName)." } ?? "Your backend is ready for device suggestions.")
                    .font(.subheadline)
            }
            Spacer()
            if let nextDevice {
                Button("Turn on") {
                    Task { await appState.toggleDevice(nextDevice) }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule(style: .continuous))
            }
        }
        .padding(20)
        .glassCard()
    }

    private func tileTint(for device: Device) -> Color {
        switch device.type {
        case .light:
            return VokrrTheme.coral
        case .sensor:
            return VokrrTheme.sky
        case .switch:
            return VokrrTheme.lavender
        case .fan:
            return VokrrTheme.sky
        case .scene, .unknown:
            return Color.white
        }
    }
}

private struct DeviceTile: View {
    let device: Device
    let emphasis: Color
    let onSelect: () -> Void
    let onToggle: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: icon)
                        .font(.title3)
                    Spacer()
                    Button(action: onToggle) {
                        Capsule(style: .continuous)
                            .fill(device.state.isOn ? VokrrTheme.lavender : Color.white.opacity(0.12))
                            .frame(width: 42, height: 24)
                            .overlay(alignment: device.state.isOn ? .trailing : .leading) {
                                Circle()
                                    .fill(device.state.isOn ? Color.black.opacity(0.78) : Color.white.opacity(0.75))
                                    .frame(width: 18, height: 18)
                                    .padding(3)
                            }
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)

                Text(device.name)
                    .font(.headline)
                    .multilineTextAlignment(.leading)

                Text(tileSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.78))
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 168, alignment: .leading)
            .glassCard(tint: emphasis)
        }
        .buttonStyle(.plain)
    }

    private var icon: String {
        switch device.type {
        case .light: return "lightbulb.fill"
        case .switch: return "tv.fill"
        case .fan: return "fan.fill"
        case .sensor: return "thermometer.medium"
        case .scene, .unknown: return "switch.2"
        }
    }

    private var tileSubtitle: String {
        if let brightness = device.state.brightness {
            return device.state.isOn ? "On · \(brightness)%" : "Off"
        }
        if let percentage = device.state.percentage {
            return device.state.isOn ? "On · \(percentage)%" : "Off"
        }
        return device.state.isOn ? "On" : "Off"
    }
}

private struct RoomSummaryCard: View {
    let room: Room
    let onSetState: (Bool) -> Void

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(room.name)
                    .font(.headline)
                Text("\(room.activeDevicesCount) on · \(room.devices.count) devices")
                    .font(.subheadline)
                    .foregroundStyle(VokrrTheme.secondaryText)
            }
            Spacer()
            HStack(spacing: 10) {
                Button("Off") {
                    onSetState(false)
                }
                .roomActionButton(active: room.activeDevicesCount == 0)
                Button("On") {
                    onSetState(true)
                }
                .roomActionButton(active: room.activeDevicesCount > 0)
            }
        }
        .padding(18)
        .glassCard()
    }
}

private extension View {
    func roomActionButton(active: Bool) -> some View {
        self
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(active ? Color.black : Color.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(active ? AnyShapeStyle(VokrrTheme.gradient) : AnyShapeStyle(Color.white.opacity(0.08)))
            .clipShape(Capsule(style: .continuous))
    }
}
