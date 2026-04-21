import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    QuantumLogo()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Quantum Home")
                            .font(.title2.bold())
                        Text("Connect directly to your Raspberry Pi control stack.")
                            .font(.footnote)
                            .foregroundStyle(QuantumTheme.secondaryText)
                    }
                    Spacer()
                }

                Group {
                    labeledField("Server", text: $appState.serverURL, icon: "network")
                    labeledField("Username", text: $appState.username, icon: "person")
                    SecureField("Password", text: $appState.password)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                }

                if !appState.loginError.isEmpty {
                    Text(appState.loginError)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.red.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    Task { await appState.login() }
                } label: {
                    HStack {
                        if appState.isBusy {
                            ProgressView()
                                .tint(Color.black)
                        }
                        Text(appState.isBusy ? "Connecting..." : "Open Controls")
                            .font(.headline)
                    }
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(QuantumTheme.gradient)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(24)
            .glassCard()
            .padding(.horizontal, 20)

            Spacer()
        }
    }

    private func labeledField(_ title: String, text: Binding<String>, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(QuantumTheme.secondaryText)
            TextField(title, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}
