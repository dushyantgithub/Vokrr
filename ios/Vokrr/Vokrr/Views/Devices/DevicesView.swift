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
            HStack(alignment: .top) {
                SectionHeader(title: "Devices", subtitle: "Live device state from the Raspberry Pi backend")
                Spacer()
                if appState.isAdmin {
                    Button("Add Device") {
                        appState.presentDeviceOnboarding()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(VokrrTheme.gradient)
                    .clipShape(Capsule(style: .continuous))
                }
            }

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

private enum OnboardingStep: Int {
    case integration
    case setup
    case discover
    case assign
}

private struct DeviceOnboardingFlow: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var appState: AppState
    @State private var step: OnboardingStep = .integration
    @State private var selectedIntegration: OnboardingIntegration?
    @State private var selectedCandidate: OnboardingCandidate?
    @State private var selectedRoomID = ""
    @State private var displayName = ""
    @State private var isFavorite = false

    private var availableCandidates: [OnboardingCandidate] {
        appState.onboardingSnapshot?.candidates.filter { !$0.alreadyImported } ?? []
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .integration:
                    integrationStep
                case .setup:
                    setupStep
                case .discover:
                    discoverStep
                case .assign:
                    assignStep
                }
            }
            .padding(20)
            .background(VokrrTheme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        appState.dismissDeviceOnboarding()
                        dismiss()
                    }
                    .foregroundStyle(Color.white)
                }
            }
        }
        .task {
            if appState.onboardingSnapshot == nil {
                await appState.refreshOnboardingSnapshot()
            }
        }
    }

    private var integrationStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: "Add Device", subtitle: "Start in Home Assistant, then import the discovered device into Vokrr")

                ForEach(appState.onboardingSnapshot?.integrations ?? []) { integration in
                    Button {
                        selectedIntegration = integration
                        step = .setup
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(integration.title)
                                .font(.headline)
                                .foregroundStyle(Color.white)
                            Text(integration.description)
                                .font(.footnote)
                                .foregroundStyle(VokrrTheme.secondaryText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .glassCard()
                    }
                    .buttonStyle(.plain)
                }

                Button("Skip straight to discovered devices") {
                    step = .discover
                }
                .font(.headline)
                .foregroundStyle(Color.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(VokrrTheme.gradient)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private var setupStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader(title: "Setup with Home Assistant", subtitle: selectedIntegration?.title ?? "Integration")

            Text(selectedIntegration?.description ?? "")
                .foregroundStyle(VokrrTheme.secondaryText)

            Button("Open Home Assistant Integrations") {
                if let url = homeAssistantHandoffURL() {
                    openURL(url)
                }
            }
            .font(.headline)
            .foregroundStyle(Color.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(VokrrTheme.gradient)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            Button("I finished setup, scan for discovered devices") {
                step = .discover
                Task { await appState.refreshOnboardingSnapshot() }
            }
            .font(.headline)
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            Spacer()
        }
    }

    private var discoverStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    SectionHeader(title: "Discover Found Devices", subtitle: "Choose a Home Assistant entity bundle to add into Vokrr")
                    Spacer()
                    Button(appState.isLoadingOnboarding ? "Refreshing..." : "Refresh") {
                        Task { await appState.refreshOnboardingSnapshot() }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(VokrrTheme.secondaryText)
                }

                if availableCandidates.isEmpty {
                    Text("No unmapped Home Assistant devices were found yet.")
                        .foregroundStyle(VokrrTheme.secondaryText)
                        .padding(18)
                        .glassCard()
                } else {
                    ForEach(availableCandidates) { candidate in
                        Button {
                            selectedCandidate = candidate
                            selectedRoomID = candidate.roomID ?? appState.onboardingSnapshot?.rooms.first?.id ?? ""
                            displayName = candidate.name
                            isFavorite = false
                            step = .assign
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(candidate.name)
                                    .font(.headline)
                                    .foregroundStyle(Color.white)
                                Text("\(candidate.domain.uppercased()) · \(candidate.entityIDs.count) entity")
                                    .font(.caption)
                                    .foregroundStyle(VokrrTheme.secondaryText)
                                Text(candidate.entityIDs.joined(separator: ", "))
                                    .font(.footnote)
                                    .foregroundStyle(VokrrTheme.secondaryText)
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(18)
                            .glassCard()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var assignStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Assign to Room", subtitle: "Confirm how the device should appear inside Vokrr")

            Text(selectedCandidate?.entityIDs.joined(separator: ", ") ?? "")
                .font(.footnote)
                .foregroundStyle(VokrrTheme.secondaryText)

            TextField("Display name", text: $displayName)
                .textInputAutocapitalization(.words)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            Picker("Room", selection: $selectedRoomID) {
                ForEach(appState.onboardingSnapshot?.rooms ?? []) { room in
                    Text(room.name).tag(room.id)
                }
            }
            .pickerStyle(.menu)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            Toggle("Favourite this device", isOn: $isFavorite)
                .toggleStyle(.switch)
                .foregroundStyle(Color.white)

            Button(appState.isImportingOnboardingCandidate ? "Saving..." : "Save to Vokrr") {
                guard let candidate = selectedCandidate else { return }
                Task {
                    let saved = await appState.importOnboardingCandidate(
                        candidateID: candidate.id,
                        roomID: selectedRoomID,
                        displayName: displayName,
                        isFavorite: isFavorite
                    )
                    if saved {
                        appState.dismissDeviceOnboarding()
                        dismiss()
                    }
                }
            }
            .font(.headline)
            .foregroundStyle(Color.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(VokrrTheme.gradient)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .disabled(selectedRoomID.isEmpty || displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || appState.isImportingOnboardingCandidate)

            Spacer()
        }
    }

    private func homeAssistantHandoffURL() -> URL? {
        let base = appState.onboardingSnapshot?.homeAssistantURL ?? appState.serverURL
        guard var components = URLComponents(string: base.hasPrefix("http") ? base : "http://\(base)") else {
            return nil
        }
        components.path = selectedIntegration?.homeAssistantPath ?? "/config/integrations/dashboard"
        return components.url
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
