import SwiftUI

struct RoutinesView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader(title: "Routines", subtitle: "Run Home Assistant scenes without editing them from the app")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(appState.scenes) { scene in
                    Button {
                        Task { await appState.runScene(scene) }
                    } label: {
                        VStack(alignment: .leading, spacing: 16) {
                            Image(systemName: "sparkles")
                                .font(.title2)
                            Spacer()
                            Text(scene.name)
                                .font(.headline)
                                .multilineTextAlignment(.leading)
                            Text("Tap to run")
                                .font(.caption)
                                .foregroundStyle(VokrrTheme.secondaryText)
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, minHeight: 180, alignment: .leading)
                        .glassCard(tint: VokrrTheme.sky)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 10)
    }
}
