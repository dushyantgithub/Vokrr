import SwiftUI
import WebKit

struct NewsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "News", subtitle: "Embedded World Monitor view from the app")

            HStack {
                Button("Open in Safari") {
                    UIApplication.shared.open(URL(string: "https://www.worldmonitor.app")!)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule(style: .continuous))

                Spacer()

                Button("Refresh") {
                    appState.selectedTab = .news
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(QuantumTheme.secondaryText)
            }

            NewsWebView()
                .frame(minHeight: 620)
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        }
        .padding(.top, 10)
    }
}

private struct NewsWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.backgroundColor = .clear
        webView.isOpaque = false
        webView.load(URLRequest(url: URL(string: "https://www.worldmonitor.app")!))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
