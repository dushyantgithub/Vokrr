import Foundation
import SwiftUI
import WebKit

@MainActor
final class AppState: ObservableObject {
    @Published var phase: AppPhase = .booting
    @Published var serverURL = AppEnvironment.defaultServerURL
    @Published var username = "admin"
    @Published var password = "admin"
    @Published var rooms: [Room] = []
    @Published var scenes: [Routine] = []
    @Published var health: HealthResponse?
    @Published var loginError = ""
    @Published var bannerMessage = ""
    @Published var notifications: [NotificationItem] = []
    @Published var selectedTab: QuantumHomeTab = .dashboard
    @Published var selectedRoomID: String?
    @Published var selectedDevice: Device?
    @Published var jarvisStatus = "idle"
    @Published var jarvisMessage = "Say “Jarvis” to start"
    @Published var isRealtimeConnected = false
    @Published var isBusy = false

    let networkMonitor = NetworkMonitor()

    private let apiClient = APIClient()
    private let realtimeClient = RealtimeClient()
    private let keychainClient = KeychainClient()
    private let defaults = UserDefaults.standard
    private var authToken: String?

    init() {
        if let storedURL = defaults.string(forKey: "serverURL"), !storedURL.isEmpty {
            serverURL = storedURL
        }
        realtimeClient.onEnvelope = { [weak self] event, data in
            Task { @MainActor [weak self] in
                self?.handleRealtimeEvent(event: event, payload: data)
            }
        }
        realtimeClient.onConnectionChanged = { [weak self] connected in
            DispatchQueue.main.async {
                self?.isRealtimeConnected = connected
            }
        }
    }

    var selectedRoom: Room? {
        rooms.first(where: { $0.id == selectedRoomID }) ?? rooms.first
    }

    var allDevices: [Device] {
        rooms.flatMap(\.devices)
    }

    var favoriteDevices: [Device] {
        Array(allDevices.prefix(4))
    }

    func bootstrap() async {
        if phase != .booting { return }
        authToken = keychainClient.loadToken()
        if let authToken {
            do {
                try await loadInitialData(using: authToken)
                phase = .ready
                connectRealtime()
                return
            } catch {
                keychainClient.clearToken()
                self.authToken = nil
            }
        }
        do {
            health = try await apiClient.fetchHealth(baseURL: serverURL)
        } catch {
            bannerMessage = error.localizedDescription
        }
        phase = .login
    }

    func login() async {
        isBusy = true
        loginError = ""
        do {
            let response = try await apiClient.login(baseURL: serverURL, username: username, password: password)
            keychainClient.saveToken(response.token)
            defaults.set(apiClient.normalizeServerURL(serverURL), forKey: "serverURL")
            authToken = response.token
            try await loadInitialData(using: response.token)
            phase = .ready
            connectRealtime()
        } catch {
            loginError = error.localizedDescription
            phase = .login
        }
        isBusy = false
    }

    func refresh() async {
        guard let authToken else { return }
        do {
            try await loadInitialData(using: authToken)
        } catch {
            bannerMessage = error.localizedDescription
        }
    }

    func saveServerURL(_ value: String) async {
        serverURL = apiClient.normalizeServerURL(value)
        defaults.set(serverURL, forKey: "serverURL")
        if let token = authToken {
            realtimeClient.disconnect()
            do {
                try await loadInitialData(using: token)
                connectRealtime()
            } catch {
                bannerMessage = error.localizedDescription
            }
        }
    }

    func signOut() {
        keychainClient.clearToken()
        realtimeClient.disconnect()
        authToken = nil
        rooms = []
        scenes = []
        selectedRoomID = nil
        notifications = []
        phase = .login
    }

    func clearNewsCache() {
        let dataStore = WKWebsiteDataStore.default()
        dataStore.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: records) { }
        }
        pushNotification(title: "Cache cleared", detail: "The embedded news session was reset.", level: .info)
    }

    func toggleDevice(_ device: Device) async {
        guard let token = authToken else { return }
        do {
            let updated = try await apiClient.toggleDevice(baseURL: serverURL, token: token, deviceID: device.id)
            mergeDevice(updated)
            pushNotification(title: updated.name, detail: updated.state.isOn ? "Turned on" : "Turned off", level: .info)
        } catch {
            bannerMessage = error.localizedDescription
        }
    }

    func setDevice(_ device: Device, request: DeviceSetRequest) async {
        guard let token = authToken else { return }
        do {
            let updated = try await apiClient.setDevice(baseURL: serverURL, token: token, deviceID: device.id, request: request)
            mergeDevice(updated)
        } catch {
            bannerMessage = error.localizedDescription
        }
    }

    func setRoomState(_ room: Room, isOn: Bool) async {
        guard let token = authToken else { return }
        do {
            let updated = try await apiClient.setRoomState(baseURL: serverURL, token: token, roomID: room.id, isOn: isOn)
            mergeRoom(updated)
            pushNotification(title: room.name, detail: isOn ? "Room powered on" : "Room powered off", level: .info)
        } catch {
            do {
                for device in room.devices where device.capabilities.contains(.toggle) {
                    let updated = try await apiClient.setDevice(
                        baseURL: serverURL,
                        token: token,
                        deviceID: device.id,
                        request: DeviceSetRequest(state: isOn)
                    )
                    mergeDevice(updated)
                }
                pushNotification(title: room.name, detail: isOn ? "Room powered on" : "Room powered off", level: .info)
            } catch {
                bannerMessage = error.localizedDescription
            }
        }
    }

    func runScene(_ scene: Routine) async {
        guard let token = authToken else { return }
        do {
            let response = try await apiClient.runScene(baseURL: serverURL, token: token, sceneID: scene.id)
            pushNotification(title: response.name, detail: "Routine executed", level: .info)
            try await loadInitialData(using: token)
        } catch {
            bannerMessage = error.localizedDescription
        }
    }

    func selectRoom(_ id: String) {
        selectedRoomID = id
    }

    private func loadInitialData(using token: String) async throws {
        async let nextHealth = apiClient.fetchHealth(baseURL: serverURL)
        async let nextRooms = apiClient.fetchRooms(baseURL: serverURL, token: token)
        async let nextScenes = apiClient.fetchScenes(baseURL: serverURL, token: token)

        health = try await nextHealth
        rooms = try await nextRooms
        scenes = try await nextScenes
        if selectedRoomID == nil {
            selectedRoomID = rooms.first?.id
        }
    }

    private func connectRealtime() {
        guard let token = authToken, let url = try? apiClient.websocketURL(baseURL: serverURL, token: token) else {
            return
        }
        realtimeClient.connect(to: url)
    }

    private func handleRealtimeEvent(event: String, payload: Data) {
        let decoder = JSONDecoder()
        switch event {
        case "snapshot":
            if let wrapped = try? decoder.decode(SnapshotPayload.self, from: payload) {
                rooms = wrapped.rooms
                selectedRoomID = selectedRoomID ?? wrapped.rooms.first?.id
            }
        case "device.updated":
            if let updated = try? decoder.decode(Device.self, from: payload) {
                mergeDevice(updated)
            }
        case "voice.status":
            if let status = try? decoder.decode(VoiceStatusPayload.self, from: payload) {
                jarvisStatus = status.status
                jarvisMessage = status.message
            }
        case "voice.command":
            if let command = try? decoder.decode(VoiceCommandPayload.self, from: payload) {
                jarvisStatus = command.understood ? "done" : "command_error"
                jarvisMessage = command.message
                if let destination = command.navigate,
                   let tab = QuantumHomeTab.allCases.first(where: { $0.rawValue == destination }) {
                    selectedTab = tab
                }
                if !command.understood {
                    pushNotification(title: "Jarvis", detail: command.message, level: .error)
                }
            }
        case "scene.ran":
            if let ran = try? decoder.decode(SceneRunResponse.self, from: payload) {
                pushNotification(title: ran.name, detail: "Routine completed", level: .info)
            }
        default:
            break
        }
    }

    private func mergeDevice(_ updatedDevice: Device) {
        rooms = rooms.map { room in
            var room = room
            room.devices = room.devices.map { device in
                device.id == updatedDevice.id ? updatedDevice : device
            }
            return room
        }
        if selectedDevice?.id == updatedDevice.id {
            selectedDevice = updatedDevice
        }
    }

    private func mergeRoom(_ updatedRoom: Room) {
        rooms = rooms.map { $0.id == updatedRoom.id ? updatedRoom : $0 }
    }

    private func pushNotification(title: String, detail: String, level: NotificationLevel) {
        notifications.insert(
            NotificationItem(title: title, detail: detail, date: Date(), level: level),
            at: 0
        )
        notifications = Array(notifications.prefix(20))
    }
}

private struct SnapshotPayload: Decodable {
    let rooms: [Room]
}
