import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var energyRingSpinning = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            Group {
                if let room = appState.selectedRoom {
                    roomDetail(room)
                } else {
                    roomOverview
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 130)
        }
        .background(VokrrTheme.background)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 26).repeatForever(autoreverses: false)) {
                energyRingSpinning = true
            }
        }
    }

    private var roomOverview: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(greeting)
                        .font(VokrrTheme.mono(9))
                        .tracking(3)
                        .foregroundStyle(VokrrTheme.tertiaryText)
                    Text(appState.displayName)
                        .font(VokrrTheme.jost(30))
                        .tracking(1)
                }
                Spacer(minLength: 12)
                VokrrConnectionBadge(isConnected: appState.isPreviewMode || appState.isRealtimeConnected)
            }

            energyHero
                .padding(.top, 22)

            HStack(alignment: .firstTextBaseline) {
                Text("Rooms")
                    .font(VokrrTheme.jost(17))
                    .tracking(1.5)
                Spacer()
                Button {
                    Task { await appState.turnEverythingOff() }
                } label: {
                    Text("ALL OFF")
                        .font(VokrrTheme.mono(8))
                        .tracking(2)
                        .foregroundStyle(VokrrTheme.champagne)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .overlay(Capsule().stroke(VokrrTheme.champagne.opacity(0.20)))
                }
                .buttonStyle(VokrrPressStyle())
            }
            .padding(.horizontal, 2)
            .padding(.top, 26)
            .padding(.bottom, 12)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())],
                spacing: 10
            ) {
                ForEach(appState.rooms) { room in
                    RoomCard(room: room) {
                        if reduceMotion {
                            appState.selectRoom(room.id)
                        } else {
                            withAnimation(VokrrTheme.roomEntrance) { appState.selectRoom(room.id) }
                        }
                    }
                }
            }

            if appState.rooms.isEmpty {
                Text("NO ROOMS AVAILABLE")
                    .font(VokrrTheme.mono(8))
                    .tracking(2)
                    .foregroundStyle(VokrrTheme.tertiaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 48)
            }
        }
    }

    private var energyHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("LIVE DRAW")
                .font(VokrrTheme.mono(8))
                .tracking(2.5)
                .foregroundStyle(VokrrTheme.secondaryText)
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text("\(appState.liveWatts)")
                    .font(VokrrTheme.jost(46))
                Text("W")
                    .font(VokrrTheme.mono(10))
                    .foregroundStyle(VokrrTheme.champagne)
            }
            .padding(.top, 4)
            HStack(spacing: 18) {
                Text("\(appState.activeDevicesCount) DEVICES ON")
                    .foregroundStyle(VokrrTheme.emerald)
                Text("\(appState.rooms.count) ROOMS")
                Text("LIVE")
            }
            .font(VokrrTheme.mono(8))
            .tracking(1.5)
            .foregroundStyle(VokrrTheme.tertiaryText)
            .padding(.top, 14)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [VokrrTheme.emerald.opacity(0.12), VokrrTheme.emerald.opacity(0.02), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .background(VokrrTheme.champagne.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(VokrrTheme.emerald.opacity(0.22)))
        .overlay(alignment: .topTrailing) {
            Circle()
                .stroke(VokrrTheme.emerald.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
                .frame(width: 160, height: 160)
                .offset(x: 40, y: -40)
                .rotationEffect(.degrees(energyRingSpinning ? 360 : 0))
                .allowsHitTesting(false)
        }
        .clipped()
    }

    private func roomDetail(_ room: Room) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    if reduceMotion {
                        appState.closeRoom()
                    } else {
                        withAnimation(VokrrTheme.roomEntrance) { appState.closeRoom() }
                    }
                } label: {
                    Circle()
                        .stroke(VokrrTheme.champagne.opacity(0.25))
                        .frame(width: 36, height: 36)
                        .overlay {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 15, weight: .light))
                                .foregroundStyle(VokrrTheme.champagne)
                        }
                }
                .buttonStyle(VokrrPressStyle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(room.name)
                        .font(VokrrTheme.jost(22))
                        .tracking(1)
                    Text("\(room.activeDevicesCount) OF \(room.devices.count) ON · \(room.estimatedWatts)W")
                        .font(VokrrTheme.mono(7.5))
                        .tracking(2)
                        .foregroundStyle(VokrrTheme.emerald)
                }
            }

            VStack(spacing: 10) {
                ForEach(Array(room.devices.enumerated()), id: \.element.id) { index, device in
                    DeviceRow(device: device) {
                        Task { await appState.toggleDevice(device) }
                    }
                    .transition(.opacity.combined(with: .offset(y: 16)))
                    .animation(
                        reduceMotion ? nil : .easeOut(duration: 0.40).delay(Double(index) * 0.035),
                        value: room.id
                    )
                }
            }
            .padding(.top, 18)
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "GOOD MORNING" }
        if hour < 18 { return "GOOD AFTERNOON" }
        return "GOOD EVENING"
    }
}

private struct RoomCard: View {
    let room: Room
    let action: () -> Void

    var body: some View {
        let active = room.activeDevicesCount > 0
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: roomIcon)
                        .font(.system(size: 21, weight: .light))
                        .foregroundStyle(active ? VokrrTheme.emerald : VokrrTheme.champagne)
                    Spacer()
                    Circle()
                        .fill(active ? VokrrTheme.emerald : VokrrTheme.champagne.opacity(0.20))
                        .frame(width: 6, height: 6)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(room.name)
                        .font(VokrrTheme.jost(15))
                        .tracking(0.5)
                        .lineLimit(1)
                    Text(active ? "\(room.activeDevicesCount) ON" : "ALL OFF")
                        .font(VokrrTheme.mono(7.5))
                        .tracking(1.5)
                        .foregroundStyle(active ? VokrrTheme.emerald : VokrrTheme.tertiaryText)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
            .background(active ? VokrrTheme.emerald.opacity(0.07) : VokrrTheme.champagne.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(active ? VokrrTheme.emerald.opacity(0.25) : VokrrTheme.champagne.opacity(0.10))
            )
        }
        .buttonStyle(VokrrPressStyle())
    }

    private var roomIcon: String {
        let name = room.name.lowercased()
        if name.contains("living") { return "sofa" }
        if name.contains("kitchen") { return "fork.knife" }
        if name.contains("gaming") { return "gamecontroller" }
        if name.contains("bed") { return "bed.double" }
        if name.contains("bath") { return "drop" }
        if name.contains("dining") { return "fork.knife.circle" }
        return room.icon.isEmpty ? "square.grid.2x2" : room.icon
    }
}

private struct DeviceRow: View {
    let device: Device
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 15) {
                Image(systemName: icon)
                    .font(.system(size: 21, weight: .light))
                    .foregroundStyle(device.state.isOn ? VokrrTheme.emerald : VokrrTheme.secondaryText)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(VokrrTheme.jost(16))
                        .tracking(0.5)
                    Text(device.state.isOn ? "ON · \(device.estimatedWatts)W" : "OFF")
                        .font(VokrrTheme.mono(7.5))
                        .tracking(1.5)
                        .foregroundStyle(device.state.isOn ? VokrrTheme.emerald : VokrrTheme.tertiaryText)
                }
                Spacer()
                VokrrToggle(isOn: device.state.isOn)
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 72)
            .background(device.state.isOn ? VokrrTheme.emerald.opacity(0.08) : VokrrTheme.champagne.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(device.state.isOn ? VokrrTheme.emerald.opacity(0.30) : VokrrTheme.champagne.opacity(0.10))
            )
        }
        .buttonStyle(VokrrPressStyle())
    }

    private var icon: String {
        let name = device.name.lowercased()
        if name.contains("tube") { return "light.recessed.3" }
        if name.contains("aircon") { return "air.conditioner.horizontal" }
        if name.contains("geyser") { return "water.waves" }
        return switch device.type {
        case .light: "lightbulb"
        case .fan: "fan"
        case .switch: "poweroutlet.type.f"
        case .sensor: "sensor"
        case .scene: "sparkles"
        case .unknown: "switch.2"
        }
    }
}
