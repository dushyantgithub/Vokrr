import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var draftServerURL = ""
    @State private var newUsername = ""
    @State private var newPassword = ""
    @State private var newUserIsAdmin = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader(title: "Settings", subtitle: "Connection, session, and admin controls")

            VStack(alignment: .leading, spacing: 12) {
                Text("Server")
                    .font(.headline)
                TextField("Backend URL", text: Binding(
                    get: { draftServerURL.isEmpty ? appState.serverURL : draftServerURL },
                    set: { draftServerURL = $0 }
                ))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                Button("Save server and reconnect") {
                    Task {
                        await appState.saveServerURL(draftServerURL.isEmpty ? appState.serverURL : draftServerURL)
                    }
                }
                .font(.headline)
                .foregroundStyle(Color.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(VokrrTheme.gradient)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .padding(20)
            .glassCard()

            VStack(alignment: .leading, spacing: 12) {
                Text("Current session")
                    .font(.headline)
                Text("Username: \(appState.username)")
                    .foregroundStyle(VokrrTheme.secondaryText)
                Text("Role: \(appState.isAdmin ? "Admin" : "Standard")")
                    .foregroundStyle(VokrrTheme.secondaryText)
                Text("Role gating comes from the persisted session and is refreshed from the backend on load.")
                    .font(.footnote)
                    .foregroundStyle(VokrrTheme.secondaryText)
            }
            .padding(20)
            .glassCard()

            if appState.isAdmin {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Admin tools")
                        .font(.headline)
                    Text("User creation is managed here on iPhone only.")
                        .font(.footnote)
                        .foregroundStyle(VokrrTheme.secondaryText)

                    Button(appState.isRestartingSystem ? "Restarting..." : "Restart Raspberry Pi") {
                        Task { await appState.restartSystem() }
                    }
                    .font(.headline)
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.orange.opacity(0.20))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .disabled(appState.isRestartingSystem)

                    TextField("Username", text: $newUsername)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    SecureField("Password", text: $newPassword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    Toggle("Admin user", isOn: $newUserIsAdmin)
                        .toggleStyle(.switch)
                        .foregroundStyle(Color.white)

                    Button(appState.isCreatingUser ? "Saving..." : "Create user") {
                        Task {
                            await appState.createUser(
                                username: newUsername,
                                password: newPassword,
                                isAdmin: newUserIsAdmin
                            )
                            if appState.settingsMessage.hasPrefix("User ") {
                                newUsername = ""
                                newPassword = ""
                                newUserIsAdmin = false
                            }
                        }
                    }
                    .font(.headline)
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(VokrrTheme.gradient)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .disabled(appState.isCreatingUser || newUsername.count < 3 || newPassword.count < 12)
                }
                .padding(20)
                .glassCard()
            }

            if !appState.settingsMessage.isEmpty {
                Text(appState.settingsMessage)
                    .font(.footnote)
                    .foregroundStyle(VokrrTheme.secondaryText)
                    .padding(.horizontal, 4)
            }

            Button("Clear news cache") {
                appState.clearNewsCache()
            }
            .font(.headline)
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            Button("Sign out") {
                appState.signOut()
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.red.opacity(0.20))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(.top, 10)
        .onAppear {
            draftServerURL = appState.serverURL
        }
    }
}
