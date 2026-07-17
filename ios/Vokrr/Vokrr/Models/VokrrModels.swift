import Foundation

enum VokrrTab: String, CaseIterable, Identifiable {
    case home = "Home"
    case health = "Health"
    case jarvis = "Jarvis"
    case settings = "Settings"

    var id: String { rawValue }
}

enum Capability: String, Codable {
    case toggle
    case brightness
    case percentage
    case temperature
    case colorTemperature = "color_temperature"
    case color
}

enum DeviceType: String, Codable {
    case light
    case `switch`
    case fan
    case sensor
    case scene
    case unknown
}

struct DeviceState: Codable, Equatable {
    var state: String
    var isOn: Bool
    var brightness: Int?
    var percentage: Int?
    var colorTempKelvin: Int?
    var rgbColor: [Int]?

    enum CodingKeys: String, CodingKey {
        case state
        case isOn = "is_on"
        case brightness
        case percentage
        case colorTempKelvin = "color_temp_kelvin"
        case rgbColor = "rgb_color"
    }
}

struct Device: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let type: DeviceType
    let entityID: String
    let roomID: String
    let roomName: String
    let capabilities: [Capability]
    var state: DeviceState

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case type
        case entityID = "entity_id"
        case roomID = "room_id"
        case roomName = "room_name"
        case capabilities
        case state
    }

    var levelValue: Double {
        Double(state.brightness ?? state.percentage ?? 0)
    }

    var supportsLevel: Bool {
        capabilities.contains(.brightness) || capabilities.contains(.percentage)
    }

    var supportsColorTemperature: Bool {
        capabilities.contains(.colorTemperature)
    }

    var estimatedWatts: Int {
        guard state.isOn else { return 0 }
        let normalized = "\(name) \(entityID)".lowercased()
        if normalized.contains("geyser") { return 2_000 }
        if normalized.contains("aircon") || normalized.contains("ac ") { return 1_200 }
        if normalized.contains("fan") { return 45 }
        if normalized.contains("socket") { return 30 }
        if normalized.contains("tube") { return 18 }
        if normalized.contains("bulb") || type == .light { return 9 }
        return type == .switch ? 12 : 0
    }
}

struct Room: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let icon: String
    var devices: [Device]

    var activeDevicesCount: Int {
        devices.filter(\.state.isOn).count
    }

    var canToggle: Bool {
        devices.contains { $0.capabilities.contains(.toggle) }
    }

    var estimatedWatts: Int {
        devices.reduce(0) { $0 + $1.estimatedWatts }
    }
}

struct Routine: Codable, Identifiable, Equatable {
    let id: String
    let name: String
}

struct SessionUser: Codable, Equatable {
    let id: String
    let username: String
    let isAdmin: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case isAdmin = "is_admin"
    }
}

struct AuthSession: Codable, Equatable {
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

struct CreateUserRequest: Encodable {
    let username: String
    let password: String
    let isAdmin: Bool

    enum CodingKeys: String, CodingKey {
        case username
        case password
        case isAdmin = "is_admin"
    }
}

struct SystemRestartResponse: Codable {
    let accepted: Bool
    let detail: String
}

struct OnboardingIntegration: Codable, Identifiable, Equatable {
    let domain: String
    let title: String
    let description: String
    let setupKind: String
    let homeAssistantPath: String
    let icon: String?

    var id: String { domain }

    enum CodingKeys: String, CodingKey {
        case domain
        case title
        case description
        case setupKind = "setup_kind"
        case homeAssistantPath = "home_assistant_path"
        case icon
    }
}

struct OnboardingRoomOption: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let icon: String
}

struct OnboardingCandidate: Codable, Identifiable, Equatable {
    let id: String
    let entityID: String
    let entityIDs: [String]
    let haDeviceID: String?
    let name: String
    let domain: String
    let platform: String?
    let areaID: String?
    let roomID: String?
    let roomName: String?
    let type: DeviceType
    let capabilities: [Capability]
    let state: DeviceState
    let alreadyImported: Bool
    let existingDeviceID: String?

    enum CodingKeys: String, CodingKey {
        case id
        case entityID = "entity_id"
        case entityIDs = "entity_ids"
        case haDeviceID = "ha_device_id"
        case name
        case domain
        case platform
        case areaID = "area_id"
        case roomID = "room_id"
        case roomName = "room_name"
        case type
        case capabilities
        case state
        case alreadyImported = "already_imported"
        case existingDeviceID = "existing_device_id"
    }
}

struct OnboardingSnapshotResponse: Codable, Equatable {
    let integrations: [OnboardingIntegration]
    let candidates: [OnboardingCandidate]
    let rooms: [OnboardingRoomOption]
    let homeAssistantURL: String

    enum CodingKeys: String, CodingKey {
        case integrations
        case candidates
        case rooms
        case homeAssistantURL = "home_assistant_url"
    }
}

struct DeviceImportRequest: Encodable {
    let candidateID: String
    let roomID: String
    let displayName: String?
    let isVisible: Bool
    let isFavorite: Bool
    let capabilitiesOverride: [Capability]?

    enum CodingKeys: String, CodingKey {
        case candidateID = "candidate_id"
        case roomID = "room_id"
        case displayName = "display_name"
        case isVisible = "is_visible"
        case isFavorite = "is_favorite"
        case capabilitiesOverride = "capabilities_override"
    }
}

struct HealthResponse: Codable {
    struct HomeAssistantStatus: Codable {
        let ok: Bool
        let error: String?
    }

    let ok: Bool
    let homeAssistant: HomeAssistantStatus

    enum CodingKeys: String, CodingKey {
        case ok
        case homeAssistant = "home_assistant"
    }
}

struct DeviceSetRequest: Encodable {
    var state: Bool?
    var brightness: Int?
    var percentage: Int?
    var colorTempKelvin: Int?
    var rgbColor: [Int]?

    enum CodingKeys: String, CodingKey {
        case state
        case brightness
        case percentage
        case colorTempKelvin = "color_temp_kelvin"
        case rgbColor = "rgb_color"
    }
}

struct RoomSetRequest: Encodable {
    let state: Bool
}

struct SceneRunResponse: Codable {
    let id: String
    let name: String
    let executedActions: Int

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case executedActions = "executed_actions"
    }
}

struct VoiceStatusPayload: Codable {
    let status: String
    let message: String
}

struct VoiceCommandPayload: Codable {
    let understood: Bool
    let message: String
    let matchedDeviceIDs: [String]
    let navigate: String?

    enum CodingKeys: String, CodingKey {
        case understood
        case message
        case matchedDeviceIDs = "matched_device_ids"
        case navigate
    }
}

struct JarvisChatMessage: Identifiable, Equatable {
    enum Speaker: Equatable {
        case user
        case jarvis
    }

    let id = UUID()
    let speaker: Speaker
    let text: String
}

struct NotificationItem: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let detail: String
    let date: Date
    let level: NotificationLevel
}

enum NotificationLevel {
    case info
    case warning
    case error
}

enum AppPhase {
    case booting
    case login
    case ready
}
