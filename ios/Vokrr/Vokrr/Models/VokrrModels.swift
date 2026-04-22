import Foundation

enum VokrrTab: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case devices = "Devices"
    case routines = "Routines"
    case activity = "Activity"
    case news = "News"
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
