import SwiftUI

struct DevicesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""

    private var filteredDevices: [Device] {
        let scoped = appState.selectedRoom.map { room in
            appState.allDevices.filter { $0.roomID == room.id }
        } ?? appState.allDevices

        guard !searchText.isEmpty else { return scoped }
        return scoped.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.roomName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader(title: "Devices", subtitle: "Live device state from the Raspberry Pi backend")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(appState.rooms) { room in
                        Button {
                            appState.selectRoom(room.id)
                        } label: {
                            TabPill(title: room.name, isActive: appState.selectedRoom?.id == room.id)
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(VokrrTheme.secondaryText)
                TextField("Search devices", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .glassCard()

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 2), spacing: 14) {
                ForEach(filteredDevices) { device in
                    DeviceControlCard(device: device)
                }
            }
        }
        .padding(.top, 10)
    }
}

private struct DeviceControlCard: View {
    @EnvironmentObject private var appState: AppState
    let device: Device
    @State private var sliderValue: Double

    init(device: Device) {
        self.device = device
        _sliderValue = State(initialValue: device.levelValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(VokrrTheme.secondaryText)
                Spacer()
                Button {
                    Task { await appState.toggleDevice(device) }
                } label: {
                    Image(systemName: device.state.isOn ? "power.circle.fill" : "power.circle")
                        .font(.title3)
                        .foregroundStyle(device.state.isOn ? VokrrTheme.lavender : Color.white.opacity(0.7))
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(device.name)
                    .font(.headline)
                Text(device.roomName)
                    .font(.caption)
                    .foregroundStyle(VokrrTheme.secondaryText)
            }

            Spacer(minLength: 0)

            if device.supportsLevel {
                VStack(spacing: 8) {
                    Slider(value: $sliderValue, in: 0 ... 100, step: 1) { editing in
                        if !editing {
                            Task {
                                if device.capabilities.contains(.brightness) {
                                    await appState.setDevice(device, request: DeviceSetRequest(brightness: Int(sliderValue)))
                                } else {
                                    await appState.setDevice(device, request: DeviceSetRequest(percentage: Int(sliderValue)))
                                }
                            }
                        }
                    }
                    .tint(VokrrTheme.lavender)
                    Text("\(Int(sliderValue))%")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(VokrrTheme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else {
                Text(device.state.isOn ? "On" : "Off")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(VokrrTheme.secondaryText)
            }
        }
        .padding(18)
        .frame(minHeight: 180)
        .glassCard(tint: device.state.isOn ? VokrrTheme.lavender : .clear)
        .onTapGesture {
            appState.selectedDevice = device
        }
    }

    private var icon: String {
        switch device.type {
        case .light: return "lightbulb.fill"
        case .fan: return "fan.fill"
        case .switch: return "switch.2"
        case .sensor: return "sensor"
        case .scene, .unknown: return "switch.2"
        }
    }
}
