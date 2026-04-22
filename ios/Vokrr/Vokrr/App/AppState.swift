import Foundation
import SwiftUI
import WebKit

@MainActor
final class AppState: ObservableObject {
    @Published var phase: AppPhase = .booting
    @Published var serverURL = AppEnvironment.defaultServerURL
    @Published var username = "admin"
    @Published var password = ""
    @Published var rooms: [Room] = []
    @Published var scenes: [Routine] = []
    @Published var health: HealthResponse?
    @Published var loginError = ""
    @Published var bannerMessage = ""
    @Published var notifications: [NotificationItem] = []
    @Published var selectedTab: VokrrTab = .dashboard
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
    private var session: AuthSession?

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
        if let stored = keychainClient.loadSession() {
            do {
                let restored = AuthSession(
                    accessToken: stored.accessToken,
                    refreshToken: stored.refreshToken,
                    tokenType: "Bearer",
                    expiresIn: 0,
                    user: SessionUser(id: "", username: username, isAdmin: false)
                )
                session = restored
                try await loadInitialData()
                phase = .ready
                await connectRealtime()
                return
            } catch {
                keychainClient.clearSession()
                session = nil
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
            let nextSession = try await apiClient.login(
                baseURL: serverURL,
                username: username,
                password: password
            )
            storeSession(nextSession)
            defaults.set(apiClient.normalizeServerURL(serverURL), forKey: "serverURL")
            try await loadInitialData()
            phase = .ready
            await connectRealtime()
        } catch {
            loginError = error.localizedDescription
            phase = .login
        }
        isBusy = false
    }

    func refresh() async {
        guard session != nil else { return }
        do {
            try await loadInitialData()
        } catch {
            bannerMessage = error.localizedDescription
        }
    }

    func saveServerURL(_ value: String) async {
        serverURL = apiClient.normalizeServerURL(value)
        defaults.set(serverURL, forKey: "serverURL")
        if session != nil {
            realtimeClient.disconnect()
            do {
                try await loadInitialData()
                await connectRealtime()
            } catch {
                bannerMessage = error.localizedDescription
            }
        }
    }

    func signOut() {
        Task {
            if let session {
                try? await apiClient.logout(
                    baseURL: serverURL,
                    refreshToken: session.refreshToken,
                    accessToken: session.accessToken
                )
            }
            performLocalSignOut()
        }
    }

    func clearNewsCache() {
        let dataStore = WKWebsiteDataStore.default()
        dataStore.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: records) { }
        }
        pushNotification(title: "Cache cleared", detail: "The embedded news session was reset.", level: .info)
    }

    func toggleDevice(_ device: Device) async {
        do {
            let updated = try await withAuthorizedAccessToken { token in
                try await apiClient.toggleDevice(baseURL: serverURL, token: token, deviceID: device.id)
            }
            mergeDevice(updated)
            pushNotification(
                title: updated.name,
                detail: updated.state.isOn ? "Turned on" : "Turned off",
                level: .info
            )
        } catch {
            bannerMessage = error.localizedDescription
        }
    }

    func setDevice(_ device: Device, request: DeviceSetRequest) async {
        do {
            let updated = try await withAuthorizedAccessToken { token in
                try await apiClient.setDevice(
                    baseURL: serverURL,
                    token: token,
                    deviceID: device.id,
                    request: request
                )
            }
            mergeDevice(updated)
        } catch {
            bannerMessage = error.localizedDescription
        }
    }

    func setRoomState(_ room: Room, isOn: Bool) async {
        do {
            let updated = try await withAuthorizedAccessToken { token in
                try await apiClient.setRoomState(
                    baseURL: serverURL,
                    token: token,
                    roomID: room.id,
                    isOn: isOn
                )
            }
            mergeRoom(updated)
            pushNotification(
                title: room.name,
                detail: isOn ? "Room powered on" : "Room powered off",
                level: .info
            )
        } catch {
            do {
                try await withAuthorizedAccessToken { token in
                    for device in room.devices where device.capabilities.contains(.toggle) {
                        let updated = try await apiClient.setDevice(
                            baseURL: serverURL,
                            token: token,
                            deviceID: device.id,
                            request: DeviceSetRequest(state: isOn)
                        )
                        mergeDevice(updated)
                    }
                }
                pushNotification(
                    title: room.name,
                    detail: isOn ? "Room powered on" : "Room powered off",
                    level: .info
                )
            } catch {
                bannerMessage = error.localizedDescription
            }
        }
    }

    func runScene(_ scene: Routine) async {
        do {
            let response = try await withAuthorizedAccessToken { token in
                try await apiClient.runScene(baseURL: serverURL, token: token, sceneID: scene.id)
            }
            pushNotification(title: response.name, detail: "Routine executed", level: .info)
            try await loadInitialData()
        } catch {
            bannerMessage = error.localizedDescription
        }
    }

    func selectRoom(_ id: String) {
        selectedRoomID = id
    }

    private func loadInitialData() async throws {
        async let nextHealth = apiClient.fetchHealth(baseURL: serverURL)
        async let nextRooms = withAuthorizedAccessToken { token in
            try await apiClient.fetchRooms(baseURL: serverURL, token: token)
        }
        async let nextScenes = withAuthorizedAccessToken { token in
            try await apiClient.fetchScenes(baseURL: serverURL, token: token)
        }

        health = try await nextHealth
        rooms = try await nextRooms
        scenes = try await nextScenes
        if selectedRoomID == nil {
            selectedRoomID = rooms.first?.id
        }
    }

    private func connectRealtime() async {
        do {
            let accessToken = try await currentAccessToken()
            guard let url = try? apiClient.websocketURL(baseURL: serverURL, token: accessToken) else {
                return
            }
            realtimeClient.connect(to: url)
        } catch {
            bannerMessage = error.localizedDescription
        }
    }

    private func currentAccessToken() async throws -> String {
        try await withAuthorizedAccessToken { token in token }
    }

    private func withAuthorizedAccessToken<T>(
        _ operation: (String) async throws -> T
    ) async throws -> T {
        guard let currentSession = session else {
            throw APIError.unauthorized
        }
        do {
            return try await operation(currentSession.accessToken)
        } catch APIError.unauthorized {
            guard !currentSession.refreshToken.isEmpty else {
                performLocalSignOut()
                throw APIError.unauthorized
            }
            do {
                let refreshed = try await apiClient.refreshSession(
                    baseURL: serverURL,
                    refreshToken: currentSession.refreshToken
                )
                storeSession(refreshed)
                return try await operation(refreshed.accessToken)
            } catch {
                performLocalSignOut()
                throw error
            }
        }
    }

    private func storeSession(_ nextSession: AuthSession) {
        session = nextSession
        username = nextSession.user.username
        keychainClient.saveSession(
            accessToken: nextSession.accessToken,
            refreshToken: nextSession.refreshToken
        )
    }

    private func performLocalSignOut() {
        keychainClient.clearSession()
        realtimeClient.disconnect()
        session = nil
        rooms = []
        scenes = []
        selectedRoomID = nil
        notifications = []
        phase = .login
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
                   let tab = VokrrTab.allCases.first(where: { $0.rawValue == destination }) {
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
