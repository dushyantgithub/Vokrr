import AppIntents
import Security
import SwiftUI
import WidgetKit

private enum WidgetTheme {
    static let background = Color(red: 11 / 255, green: 14 / 255, blue: 13 / 255)
    static let primary = Color(red: 238 / 255, green: 242 / 255, blue: 239 / 255)
    static let secondary = Color(red: 95 / 255, green: 107 / 255, blue: 102 / 255)
    static let emerald = Color(red: 46 / 255, green: 199 / 255, blue: 154 / 255)
    static let champagne = Color(red: 217 / 255, green: 203 / 255, blue: 168 / 255)

    static func jost(_ size: CGFloat) -> Font { .custom("Jost-Regular", size: size) }
    static func mono(_ size: CGFloat, medium: Bool = false) -> Font {
        .custom(medium ? "IBMPlexMono-Medium" : "IBMPlexMono-Regular", size: size)
    }
}

private struct WidgetSnapshot: Codable {
    struct Device: Codable, Identifiable {
        let id: String
        let label: String
        let type: String
        var isOn: Bool
        let estimatedWatts: Int?
    }

    let updatedAt: Date
    var liveWatts: Int
    var onTotal: Int
    let recoveryScore: Int?
    let heartRate: Int?
    let steps: Int?
    let sleepSeconds: Int?
    let recoveryLabel: String
    var devices: [Device]

    static let placeholder = WidgetSnapshot(
        updatedAt: Date(),
        liveWatts: 92,
        onTotal: 4,
        recoveryScore: 82,
        heartRate: 62,
        steps: 8_432,
        sleepSeconds: 25_920,
        recoveryLabel: "OPTIMAL",
        devices: [
            .init(id: "lv_fan", label: "LIV FAN", type: "fan", isOn: true, estimatedWatts: 48),
            .init(id: "lv_tube", label: "LIV TUBE", type: "light", isOn: true, estimatedWatts: 14),
            .init(id: "bd_aircon", label: "BED AC", type: "switch", isOn: false, estimatedWatts: 0),
            .init(id: "bt_geyser", label: "GEYSER", type: "switch", isOn: false, estimatedWatts: 0),
            .init(id: "gm_tube1", label: "GAME T1", type: "light", isOn: true, estimatedWatts: 15),
            .init(id: "bd_tube1", label: "BED T1", type: "light", isOn: true, estimatedWatts: 15),
            .init(id: "kt_bulb_l", label: "KIT L", type: "light", isOn: false, estimatedWatts: 0),
            .init(id: "dn_bulb", label: "DIN BULB", type: "light", isOn: false, estimatedWatts: 0),
        ]
    )
}

private enum WidgetSharedStore {
    static let appGroup = "group.com.vokrr.shared"
    static let snapshotKey = "widgetSnapshot"
    static let serverURLKey = "serverURL"

    static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    static func load() -> WidgetSnapshot {
        guard let data = defaults?.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
            return .placeholder
        }
        return snapshot
    }

    static func save(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: snapshotKey)
    }
}

private struct WidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

private struct VokrrTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        completion(WidgetEntry(date: Date(), snapshot: context.isPreview ? .placeholder : WidgetSharedStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        let entry = WidgetEntry(date: Date(), snapshot: WidgetSharedStore.load())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

struct VokrrHealthWidget: Widget {
    let kind = "VokrrHealthWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: VokrrTimelineProvider()) { entry in
            HealthWidgetView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) { WidgetTheme.background }
        }
        .configurationDisplayName("Vokrr Health")
        .description("Recovery, heart rate, steps, and sleep from your Ultrahuman Ring.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

struct VokrrHomeWidget: Widget {
    let kind = "VokrrHomeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: VokrrTimelineProvider()) { entry in
            HomeWidgetView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) { WidgetTheme.background }
        }
        .configurationDisplayName("Vokrr Home")
        .description("Live home state with interactive device controls.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

private struct HealthWidgetView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("VOKRR")
                    .font(WidgetTheme.mono(7, medium: true))
                    .tracking(2)
                    .foregroundStyle(WidgetTheme.champagne)
                Spacer()
                Circle()
                    .fill(WidgetTheme.emerald)
                    .frame(width: 4, height: 4)
                    .shadow(color: WidgetTheme.emerald.opacity(0.9), radius: 3)
            }
            Spacer()
            HStack(spacing: 12) {
                ZStack {
                    Circle().stroke(WidgetTheme.champagne.opacity(0.12), lineWidth: 4.5)
                    Circle()
                        .trim(from: 0, to: CGFloat(snapshot.recoveryScore ?? 0) / 100)
                        .stroke(WidgetTheme.emerald, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(snapshot.recoveryScore.map(String.init) ?? "—")
                        .font(WidgetTheme.jost(17))
                        .foregroundStyle(WidgetTheme.primary)
                }
                .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: 8) {
                    metric(snapshot.heartRate.map(String.init) ?? "—", "BPM")
                    metric(stepsLabel, "STEPS")
                }
            }
            Spacer()
            Text("RECOVERY \(snapshot.recoveryLabel) · \(sleepLabel) SLEEP")
                .font(WidgetTheme.mono(6))
                .tracking(1.15)
                .foregroundStyle(WidgetTheme.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(18)
        .widgetURL(URL(string: "vokrr://health"))
    }

    private func metric(_ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(WidgetTheme.jost(15)).foregroundStyle(WidgetTheme.primary)
            Text(unit).font(WidgetTheme.mono(5.5)).tracking(1).foregroundStyle(WidgetTheme.secondary)
        }
    }

    private var stepsLabel: String {
        guard let steps = snapshot.steps else { return "—" }
        return steps >= 1_000 ? String(format: "%.1fk", Double(steps) / 1_000) : "\(steps)"
    }

    private var sleepLabel: String {
        guard let seconds = snapshot.sleepSeconds else { return "—" }
        return "\(seconds / 3_600):\(String(format: "%02d", (seconds % 3_600) / 60))"
    }
}

private struct HomeWidgetView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("VOKRR HOME")
                    .font(WidgetTheme.mono(7, medium: true))
                    .tracking(2)
                    .foregroundStyle(WidgetTheme.champagne)
                Text("\(snapshot.onTotal) ON")
                    .font(WidgetTheme.mono(7))
                    .tracking(1)
                    .foregroundStyle(WidgetTheme.emerald)
                Spacer()
                Text("\(snapshot.liveWatts) W")
                    .font(WidgetTheme.mono(7))
                    .tracking(1)
                    .foregroundStyle(WidgetTheme.secondary)
            }
            Spacer(minLength: 10)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(Array(snapshot.devices.prefix(8))) { device in
                    Button(intent: ToggleDeviceIntent(deviceID: device.id)) {
                        VStack(spacing: 5) {
                            Image(systemName: icon(for: device))
                                .font(.system(size: 15, weight: .light))
                                .foregroundStyle(device.isOn ? WidgetTheme.emerald : WidgetTheme.secondary)
                            Text(device.label)
                                .font(WidgetTheme.mono(5.5))
                                .tracking(0.35)
                                .foregroundStyle(device.isOn ? WidgetTheme.champagne : WidgetTheme.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.65)
                        }
                        .frame(maxWidth: .infinity, minHeight: 47)
                        .background(device.isOn ? WidgetTheme.emerald.opacity(0.10) : WidgetTheme.champagne.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(device.isOn ? WidgetTheme.emerald.opacity(0.30) : WidgetTheme.champagne.opacity(0.08))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }

    private func icon(for device: WidgetSnapshot.Device) -> String {
        let label = device.label.lowercased()
        if label.contains("fan") { return "fan" }
        if label.contains("tube") || device.type == "light" { return "lightbulb" }
        if label.contains("ac") { return "air.conditioner.horizontal" }
        if label.contains("geyser") { return "water.waves" }
        return "poweroutlet.type.f"
    }
}

struct ToggleDeviceIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Vokrr Device"
    static let description = IntentDescription("Toggles a device through the authenticated Vokrr Hub.")
    static let openAppWhenRun = false

    @Parameter(title: "Device ID") var deviceID: String

    init() {}

    init(deviceID: String) {
        self.deviceID = deviceID
    }

    func perform() async throws -> some IntentResult {
        try await WidgetAPI.toggle(deviceID: deviceID)
        var snapshot = WidgetSharedStore.load()
        if let index = snapshot.devices.firstIndex(where: { $0.id == deviceID }) {
            let wasOn = snapshot.devices[index].isOn
            snapshot.devices[index].isOn.toggle()
            snapshot.onTotal = max(0, snapshot.onTotal + (wasOn ? -1 : 1))
            snapshot.liveWatts = max(
                0,
                snapshot.liveWatts + (wasOn ? -1 : 1) * (snapshot.devices[index].estimatedWatts ?? 0)
            )
            WidgetSharedStore.save(snapshot)
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

private enum WidgetAPI {
    private struct SessionUser: Codable {
        let id: String
        let username: String
        let isAdmin: Bool

        enum CodingKeys: String, CodingKey {
            case id, username
            case isAdmin = "is_admin"
        }
    }

    private struct Session: Codable {
        let accessToken: String
        let refreshToken: String
        let tokenType: String
        let expiresIn: Int
        let user: SessionUser

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case tokenType = "token_type"
            case expiresIn = "expires_in"
            case user
        }
    }

    private struct RefreshRequest: Codable {
        let refreshToken: String
        enum CodingKeys: String, CodingKey { case refreshToken = "refresh_token" }
    }

    static func toggle(deviceID: String) async throws {
        guard var session = loadSession(),
              let serverURL = WidgetSharedStore.defaults?.string(forKey: WidgetSharedStore.serverURLKey) else {
            throw WidgetAPIError.notSignedIn
        }
        let first = try await toggleRequest(serverURL: serverURL, deviceID: deviceID, token: session.accessToken)
        if first == 401 {
            session = try await refresh(serverURL: serverURL, session: session)
            let retry = try await toggleRequest(serverURL: serverURL, deviceID: deviceID, token: session.accessToken)
            guard (200 ..< 300).contains(retry) else { throw WidgetAPIError.requestFailed }
        } else if !(200 ..< 300).contains(first) {
            throw WidgetAPIError.requestFailed
        }
    }

    private static func toggleRequest(serverURL: String, deviceID: String, token: String) async throws -> Int {
        guard let escaped = deviceID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/devices/\(escaped)/toggle") else {
            throw WidgetAPIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw WidgetAPIError.requestFailed }
        return http.statusCode
    }

    private static func refresh(serverURL: String, session: Session) async throws -> Session {
        guard let url = URL(string: serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/auth/refresh") else {
            throw WidgetAPIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(RefreshRequest(refreshToken: session.refreshToken))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode),
              let refreshed = try? JSONDecoder().decode(Session.self, from: data) else {
            throw WidgetAPIError.notSignedIn
        }
        saveSession(refreshed)
        return refreshed
    }

    private static func loadSession() -> Session? {
        let query = keychainQuery(returnData: true)
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    private static func saveSession(_ session: Session) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        let delete = keychainQuery(returnData: false)
        SecItemDelete(delete as CFDictionary)
        var insert = delete
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(insert as CFDictionary, nil)
    }

    private static func keychainQuery(returnData: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Vokrr.iOS",
            kSecAttrAccount as String: "authSession",
        ]
        if returnData {
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            query[kSecReturnData as String] = true
        }
        if let accessGroup = Bundle.main.object(forInfoDictionaryKey: "VokrrKeychainAccessGroup") as? String {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}

private enum WidgetAPIError: Error {
    case invalidURL
    case notSignedIn
    case requestFailed
}

@main
struct VokrrWidgetsBundle: WidgetBundle {
    var body: some Widget {
        VokrrHealthWidget()
        VokrrHomeWidget()
    }
}
