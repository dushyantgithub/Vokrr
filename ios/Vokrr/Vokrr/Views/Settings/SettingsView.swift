import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("voiceWakeEnabled") private var voiceWake = true
    @AppStorage("homeContextEnabled") private var homeContext = true
    @AppStorage("watchSyncEnabled") private var watchSync = true
    @AppStorage("knobSyncEnabled") private var knobSync = true
    @AppStorage("healthSyncEnabled") private var healthSync = true
    @State private var draftServerURL = ""
    @State private var showsAdminControls = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Settings")
                    .font(VokrrTheme.jost(30))
                    .tracking(1)

                settingsLabel("AI · JARVIS")
                SettingsPanel {
                    VStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("AI CREDENTIALS")
                                .font(VokrrTheme.mono(8))
                                .tracking(1.5)
                                .foregroundStyle(VokrrTheme.tertiaryText)
                            HStack(spacing: 10) {
                                Text("MANAGED SECURELY BY VOKRR HUB")
                                    .font(VokrrTheme.mono(10))
                                    .tracking(0.5)
                                    .foregroundStyle(VokrrTheme.emerald)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.68)
                                    .padding(.horizontal, 14)
                                    .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                                    .background(VokrrTheme.background.opacity(0.70))
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(VokrrTheme.emerald.opacity(0.25)))
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(VokrrTheme.champagne.opacity(0.20))
                                    .frame(width: 38, height: 38)
                                    .overlay {
                                        Image(systemName: "lock.shield")
                                            .font(.system(size: 14, weight: .light))
                                            .foregroundStyle(VokrrTheme.champagne)
                                    }
                            }
                            Text("SERVER-SIDE ONLY · NEVER STORED ON IPHONE")
                                .font(VokrrTheme.mono(7))
                                .tracking(1)
                                .foregroundStyle(VokrrTheme.tertiaryText)
                        }
                        .padding(.vertical, 12)

                        divider
                        SettingsValueRow(name: "Model", value: "VOKRR CORE ›")
                        divider
                        SettingsToggleRow(
                            name: "Voice wake — “Jarvis”",
                            subtitle: "ALWAYS LISTENING ON WATCH + PHONE",
                            isOn: $voiceWake
                        )
                        divider
                        SettingsToggleRow(
                            name: "Home context",
                            subtitle: "SHARE DEVICE + HEALTH STATE WITH AI",
                            isOn: $homeContext
                        )
                    }
                }

                settingsLabel("DEVICES")
                SettingsPanel {
                    VStack(spacing: 0) {
                        ConnectedDeviceRow(
                            icon: "circle.dashed",
                            name: "Ultrahuman Ring AIR",
                            status: ringStatus,
                            active: appState.healthDashboard?.sync.connected == true
                        )
                        divider
                        ConnectedDeviceRow(
                            icon: "applewatch",
                            name: "Vokrr Watch GT-W1",
                            status: "READY · HEALTH + NOTIFICATIONS",
                            active: watchSync
                        )
                        divider
                        ConnectedDeviceRow(
                            icon: "dial.medium",
                            name: "Vokrr Knob GT-K1",
                            status: appState.isPreviewMode || appState.isRealtimeConnected ? "ONLINE · HOME DOCK" : "WAITING FOR HUB",
                            active: appState.isPreviewMode || appState.isRealtimeConnected
                        )
                        divider
                        SettingsToggleRow(
                            name: "Watch sync",
                            subtitle: "HEALTH + NOTIFICATIONS OVER BLE",
                            isOn: $watchSync
                        )
                        divider
                        SettingsToggleRow(
                            name: "Vokrr sync",
                            subtitle: "REAL-TIME STATE ACROSS KNOB · PANEL · WATCH",
                            isOn: $knobSync
                        )
                        divider
                        SettingsToggleRow(
                            name: "Health sync",
                            subtitle: "ULTRAHUMAN DATA VIA SECURE VOKRR HUB",
                            isOn: $healthSync
                        )
                    }
                }

                settingsLabel("HOME HUB")
                SettingsPanel {
                    VStack(spacing: 0) {
                        hubRow("HUB", appState.health?.ok == true ? "Vokrr Hub · Online" : "Vokrr Hub · Checking", color: VokrrTheme.emerald)
                        divider
                        hubRow("SERVER", compactServer, color: VokrrTheme.primaryText)
                        divider
                        hubRow("PROTOCOL", appState.serverURL.hasPrefix("https") ? "WSS · TLS" : "LOCAL · HTTP", color: VokrrTheme.secondaryText)
                        divider
                        hubRow("DEVICES", "\(appState.allDevices.count) paired", color: VokrrTheme.secondaryText)
                    }
                }

                settingsLabel("ACCOUNT")
                SettingsPanel {
                    VStack(spacing: 12) {
                        TextField("Vokrr Hub URL", text: $draftServerURL)
                            .font(VokrrTheme.mono(11))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(.horizontal, 14)
                            .frame(height: 42)
                            .background(VokrrTheme.background.opacity(0.70))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(VokrrTheme.champagne.opacity(0.12)))

                        HStack(spacing: 10) {
                            Button("SAVE & RECONNECT") {
                                Task { await appState.saveServerURL(draftServerURL) }
                            }
                            .accountButton(tint: VokrrTheme.emerald)

                            if appState.isAdmin {
                                Button("ADMIN") { showsAdminControls = true }
                                    .accountButton(tint: VokrrTheme.champagne)
                            }
                        }

                        Button("SIGN OUT") { appState.signOut() }
                            .font(VokrrTheme.mono(8, medium: true))
                            .tracking(1.5)
                            .foregroundStyle(VokrrTheme.champagne)
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .overlay(Capsule().stroke(VokrrTheme.champagne.opacity(0.18)))
                    }
                    .padding(.vertical, 12)
                }

                Text("VOKRR iOS \(version) · GRAND TOURER")
                    .font(VokrrTheme.mono(7.5))
                    .tracking(2)
                    .foregroundStyle(VokrrTheme.tertiaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 26)
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 130)
        }
        .background(VokrrTheme.background)
        .onAppear { draftServerURL = appState.serverURL }
        .sheet(isPresented: $showsAdminControls) {
            AdminControlsSheet()
                .environmentObject(appState)
        }
    }

    private var divider: some View {
        Rectangle().fill(VokrrTheme.champagne.opacity(0.07)).frame(height: 1)
    }

    private func settingsLabel(_ text: String) -> some View {
        Text(text)
            .font(VokrrTheme.mono(9))
            .tracking(3)
            .foregroundStyle(VokrrTheme.secondaryText)
            .padding(.horizontal, 2)
            .padding(.top, 22)
            .padding(.bottom, 8)
    }

    private func hubRow(_ key: String, _ value: String, color: Color) -> some View {
        HStack {
            Text(key)
                .font(VokrrTheme.mono(8))
                .tracking(1.5)
                .foregroundStyle(VokrrTheme.tertiaryText)
            Spacer()
            Text(value)
                .font(VokrrTheme.jost(13))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .frame(minHeight: 44)
    }

    private var ringStatus: String {
        guard let sync = appState.healthDashboard?.sync else { return "SYNC PENDING" }
        if sync.connected { return sync.cached ? "CONNECTED · CACHED" : "CONNECTED · LATEST" }
        return sync.configured ? "SYNC UNAVAILABLE" : "NOT CONFIGURED"
    }

    private var compactServer: String {
        URL(string: appState.serverURL)?.host ?? appState.serverURL
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.4.2"
    }
}

private struct SettingsPanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 18)
            .background(VokrrTheme.champagne.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(VokrrTheme.champagne.opacity(0.10)))
    }
}

private struct SettingsValueRow: View {
    let name: String
    let value: String

    var body: some View {
        HStack {
            Text(name).font(VokrrTheme.jost(14))
            Spacer()
            Text(value)
                .font(VokrrTheme.mono(9))
                .tracking(1)
                .foregroundStyle(VokrrTheme.secondaryText)
        }
        .frame(minHeight: 44)
    }
}

private struct SettingsToggleRow: View {
    let name: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(VokrrTheme.jost(14))
                    Text(subtitle)
                        .font(VokrrTheme.mono(7))
                        .tracking(0.7)
                        .foregroundStyle(VokrrTheme.tertiaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                Spacer()
                VokrrToggle(isOn: isOn)
            }
            .frame(minHeight: 55)
        }
        .buttonStyle(VokrrPressStyle())
    }
}

private struct ConnectedDeviceRow: View {
    let icon: String
    let name: String
    let status: String
    let active: Bool

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 10 / 255, green: 13 / 255, blue: 12 / 255))
                .frame(width: 38, height: 46)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke((active ? VokrrTheme.emerald : VokrrTheme.champagne).opacity(0.35)))
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .ultraLight))
                        .foregroundStyle(active ? VokrrTheme.emerald : VokrrTheme.champagne)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(VokrrTheme.jost(14))
                Text(status)
                    .font(VokrrTheme.mono(7))
                    .tracking(0.7)
                    .foregroundStyle(active ? VokrrTheme.emerald : VokrrTheme.tertiaryText)
            }
            Spacer()
            Text("›")
                .font(VokrrTheme.mono(9))
                .foregroundStyle(VokrrTheme.tertiaryText)
        }
        .frame(minHeight: 66)
    }
}

private struct AdminControlsSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var password = ""
    @State private var isAdmin = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Home") {
                    Button("Add a device") {
                        dismiss()
                        appState.presentDeviceOnboarding()
                    }
                    Button(appState.isRestartingSystem ? "Restarting…" : "Restart Raspberry Pi", role: .destructive) {
                        Task { await appState.restartSystem() }
                    }
                    .disabled(appState.isRestartingSystem)
                }
                Section("Create user") {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                    SecureField("Password (12+ characters)", text: $password)
                    Toggle("Administrator", isOn: $isAdmin)
                    Button(appState.isCreatingUser ? "Creating…" : "Create user") {
                        Task { await appState.createUser(username: username, password: password, isAdmin: isAdmin) }
                    }
                    .disabled(username.count < 3 || password.count < 12 || appState.isCreatingUser)
                }
                if !appState.settingsMessage.isEmpty {
                    Section { Text(appState.settingsMessage) }
                }
            }
            .navigationTitle("Admin Controls")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private extension View {
    func accountButton(tint: Color) -> some View {
        font(VokrrTheme.mono(8, medium: true))
            .tracking(1.2)
            .foregroundStyle(VokrrTheme.background)
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(tint, in: Capsule())
    }
}
