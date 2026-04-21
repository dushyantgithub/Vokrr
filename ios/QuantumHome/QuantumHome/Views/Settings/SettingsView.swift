import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var draftServerURL = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader(title: "Settings", subtitle: "Connection settings and session controls")

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
                .background(QuantumTheme.gradient)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .padding(20)
            .glassCard()

            VStack(alignment: .leading, spacing: 12) {
                Text("Current login")
                    .font(.headline)
                Text("Username: \(appState.username)")
                    .foregroundStyle(QuantumTheme.secondaryText)
                Text("This app can change room and device states, but it does not add or remove devices or rooms yet.")
                    .font(.footnote)
                    .foregroundStyle(QuantumTheme.secondaryText)
            }
            .padding(20)
            .glassCard()

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
