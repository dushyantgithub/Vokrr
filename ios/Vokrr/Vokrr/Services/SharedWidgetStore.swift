import Foundation
import WidgetKit

struct VokrrWidgetSnapshot: Codable {
    struct WidgetDevice: Codable, Identifiable {
        let id: String
        let label: String
        let type: String
        let isOn: Bool
        let estimatedWatts: Int?
    }

    let updatedAt: Date
    let liveWatts: Int
    let onTotal: Int
    let recoveryScore: Int?
    let heartRate: Int?
    let steps: Int?
    let sleepSeconds: Int?
    let recoveryLabel: String
    let devices: [WidgetDevice]
}

enum SharedWidgetStore {
    static let appGroup = "group.com.vokrr.shared"
    static let snapshotKey = "widgetSnapshot"
    static let serverURLKey = "serverURL"

    static func save(
        rooms: [Room],
        health: HealthDashboardResponse?,
        serverURL: String
    ) {
        let allDevices = rooms.flatMap(\.devices)
        let current = health?.current
        let devices = Array(allDevices.prefix(8)).map {
            VokrrWidgetSnapshot.WidgetDevice(
                id: $0.id,
                label: compactLabel(for: $0),
                type: $0.type.rawValue,
                isOn: $0.state.isOn,
                estimatedWatts: $0.estimatedWatts
            )
        }
        let recovery = current?.recovery.score?.value.rounded().map(Int.init)
        let snapshot = VokrrWidgetSnapshot(
            updatedAt: Date(),
            liveWatts: allDevices.reduce(0) { $0 + $1.estimatedWatts },
            onTotal: allDevices.filter(\.state.isOn).count,
            recoveryScore: recovery,
            heartRate: current?.latestHeartRate?.value.rounded().map(Int.init),
            steps: current?.activity.steps?.value.rounded().map(Int.init),
            sleepSeconds: current?.sleep.totalSleepSeconds,
            recoveryLabel: recovery.map { $0 >= 80 ? "OPTIMAL" : ($0 >= 60 ? "GOOD" : "REST") } ?? "SYNCING",
            devices: devices
        )
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
        defaults.set(serverURL, forKey: serverURLKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func compactLabel(for device: Device) -> String {
        let room = device.roomName
            .split(separator: " ")
            .first
            .map { String($0.prefix(4)).uppercased() } ?? "HOME"
        let deviceName = device.name
            .split(separator: " ")
            .map { String($0.prefix(1)).uppercased() }
            .joined()
        return "\(room) \(deviceName.isEmpty ? String(device.name.prefix(4)).uppercased() : deviceName)"
    }
}

private extension Double {
    func map<T>(_ transform: (Double) -> T) -> T {
        transform(self)
    }
}
