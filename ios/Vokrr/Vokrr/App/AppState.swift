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
    @Published var healthDashboard: HealthDashboardResponse?
    @Published var isRefreshingHealth = false
    @Published var loginError = ""
    @Published var bannerMessage = ""
    @Published var settingsMessage = ""
    @Published var notifications: [NotificationItem] = []
    @Published var selectedTab: VokrrTab = .home
    @Published var selectedRoomID: String?
    @Published var selectedDevice: Device?
    @Published var jarvisStatus = "idle"
    @Published var jarvisMessage = "Say “Jarvis” to start"
    @Published var jarvisChat: [JarvisChatMessage] = [
        JarvisChatMessage(
            speaker: .jarvis,
            text: "Good evening. Home is steady — recovery and live device state are ready. What do you need?"
        )
    ]
    @Published var isRealtimeConnected = false
    @Published var isBusy = false
    @Published var isCreatingUser = false
    @Published var isRestartingSystem = false
    @Published var isDeviceOnboardingPresented = false
    @Published var onboardingSnapshot: OnboardingSnapshotResponse?
    @Published var isLoadingOnboarding = false
    @Published var isImportingOnboardingCandidate = false

    let networkMonitor = NetworkMonitor()

    private let apiClient = APIClient()
    private let realtimeClient = RealtimeClient()
    private let keychainClient = KeychainClient()
    private let defaults = UserDefaults.standard
    private var session: AuthSession?

    let isPreviewMode = ProcessInfo.processInfo.arguments.contains("-VOKRRPreviewMode")

    init() {
        let launchArguments = ProcessInfo.processInfo.arguments
        if isPreviewMode,
           let tabArgumentIndex = launchArguments.firstIndex(of: "-VOKRRPreviewTab"),
           launchArguments.indices.contains(tabArgumentIndex + 1),
           let launchTab = VokrrTab.allCases.first(where: {
               $0.rawValue.caseInsensitiveCompare(launchArguments[tabArgumentIndex + 1]) == .orderedSame
           }) {
            selectedTab = launchTab
        }
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
        guard let selectedRoomID else { return nil }
        return rooms.first(where: { $0.id == selectedRoomID })
    }

    var allDevices: [Device] {
        rooms.flatMap(\.devices)
    }

    var favoriteDevices: [Device] {
        Array(allDevices.prefix(8))
    }

    var liveWatts: Int {
        allDevices.reduce(0) { $0 + $1.estimatedWatts }
    }

    var activeDevicesCount: Int {
        allDevices.filter(\.state.isOn).count
    }

    var displayName: String {
        let value = currentUser?.username ?? username
        return value.prefix(1).uppercased() + value.dropFirst()
    }

    func bootstrap() async {
        if phase != .booting { return }
        if isPreviewMode {
            username = "Dushyant"
            rooms = PreviewFixtures.rooms
            healthDashboard = PreviewFixtures.health
            health = HealthResponse(ok: true, homeAssistant: .init(ok: true, error: nil))
            phase = .ready
            saveWidgetSnapshot()
            return
        }
        if let stored = keychainClient.loadSession() {
            do {
                session = stored
                username = stored.user.username
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
        if isPreviewMode {
            var updated = device
            updated.state.isOn.toggle()
            updated.state.state = updated.state.isOn ? "on" : "off"
            mergeDevice(updated)
            saveWidgetSnapshot()
            return
        }
        do {
            let updated = try await withAuthorizedAccessToken { token in
                try await apiClient.toggleDevice(baseURL: serverURL, token: token, deviceID: device.id)
            }
            mergeDevice(updated)
            saveWidgetSnapshot()
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
        if isPreviewMode {
            var updated = device
            if let state = request.state {
                updated.state.isOn = state
                updated.state.state = state ? "on" : "off"
            }
            mergeDevice(updated)
            saveWidgetSnapshot()
            return
        }
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
            saveWidgetSnapshot()
        } catch {
            bannerMessage = error.localizedDescription
        }
    }

    func setRoomState(_ room: Room, isOn: Bool) async {
        if isPreviewMode {
            var updated = room
            updated.devices = updated.devices.map { device in
                var next = device
                next.state.isOn = isOn
                next.state.state = isOn ? "on" : "off"
                return next
            }
            mergeRoom(updated)
            saveWidgetSnapshot()
            return
        }
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
            saveWidgetSnapshot()
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
                saveWidgetSnapshot()
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

    func closeRoom() {
        selectedRoomID = nil
    }

    func turnEverythingOff() async {
        for room in rooms where room.activeDevicesCount > 0 {
            await setRoomState(room, isOn: false)
        }
    }

    func refreshHealthDashboard(force: Bool = false) async {
        guard !isRefreshingHealth else { return }
        if isPreviewMode {
            healthDashboard = PreviewFixtures.health
            return
        }
        isRefreshingHealth = true
        defer { isRefreshingHealth = false }
        do {
            let dashboard = try await withAuthorizedAccessToken { token in
                if force {
                    return try await apiClient.refreshHealthDashboard(baseURL: serverURL, token: token)
                }
                return try await apiClient.fetchHealthDashboard(baseURL: serverURL, token: token)
            }
            healthDashboard = dashboard
            saveWidgetSnapshot()
        } catch {
            bannerMessage = error.localizedDescription
        }
    }

    func sendJarvisCommand(_ rawText: String) async {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, jarvisStatus != "processing" else { return }
        jarvisChat.append(JarvisChatMessage(speaker: .user, text: text))
        jarvisStatus = "processing"
        jarvisMessage = "Thinking…"

        if isPreviewMode {
            try? await Task.sleep(for: .milliseconds(700))
            let answer = previewJarvisReply(for: text)
            jarvisChat.append(JarvisChatMessage(speaker: .jarvis, text: answer))
            jarvisStatus = "done"
            jarvisMessage = answer
            return
        }

        do {
            let response = try await withAuthorizedAccessToken { token in
                try await apiClient.sendVoiceCommand(baseURL: serverURL, token: token, text: text)
            }
            jarvisChat.append(JarvisChatMessage(speaker: .jarvis, text: response.message))
            jarvisStatus = response.understood ? "done" : "command_error"
            jarvisMessage = response.message
            try? await loadInitialData()
        } catch {
            jarvisStatus = "command_error"
            jarvisMessage = error.localizedDescription
            jarvisChat.append(JarvisChatMessage(speaker: .jarvis, text: error.localizedDescription))
        }
    }

    private func loadInitialData() async throws {
        async let nextHealth = apiClient.fetchHealth(baseURL: serverURL)
        async let nextUser = withAuthorizedAccessToken { token in
            try await apiClient.fetchCurrentUser(baseURL: serverURL, token: token)
        }
        async let nextRooms = withAuthorizedAccessToken { token in
            try await apiClient.fetchRooms(baseURL: serverURL, token: token)
        }
        async let nextScenes = withAuthorizedAccessToken { token in
            try await apiClient.fetchScenes(baseURL: serverURL, token: token)
        }

        health = try await nextHealth
        let user = try await nextUser
        rooms = try await nextRooms
        scenes = try await nextScenes
        syncSessionUser(user)
        selectedRoomID = nil
        if user.isAdmin {
            healthDashboard = try? await withAuthorizedAccessToken { token in
                try await apiClient.fetchHealthDashboard(baseURL: serverURL, token: token)
            }
        }
        saveWidgetSnapshot()
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
            nextSession
        )
    }

    private func syncSessionUser(_ user: SessionUser) {
        guard let currentSession = session else { return }
        guard currentSession.user != user else {
            username = user.username
            return
        }
        let updatedSession = AuthSession(
            accessToken: currentSession.accessToken,
            refreshToken: currentSession.refreshToken,
            tokenType: currentSession.tokenType,
            expiresIn: currentSession.expiresIn,
            user: user
        )
        storeSession(updatedSession)
    }

    private func performLocalSignOut() {
        keychainClient.clearSession()
        realtimeClient.disconnect()
        session = nil
        rooms = []
        scenes = []
        healthDashboard = nil
        selectedRoomID = nil
        notifications = []
        settingsMessage = ""
        phase = .login
    }

    var currentUser: SessionUser? {
        session?.user
    }

    var isAdmin: Bool {
        currentUser?.isAdmin ?? false
    }

    func createUser(username: String, password: String, isAdmin: Bool) async {
        self.isCreatingUser = true
        settingsMessage = ""
        do {
            let created = try await withAuthorizedAccessToken { token in
                try await apiClient.createUser(
                    baseURL: serverURL,
                    token: token,
                    request: CreateUserRequest(username: username, password: password, isAdmin: isAdmin)
                )
            }
            settingsMessage = "User \(created.username) created."
            pushNotification(title: created.username, detail: "User created", level: .info)
        } catch {
            settingsMessage = error.localizedDescription
        }
        self.isCreatingUser = false
    }

    func restartSystem() async {
        isRestartingSystem = true
        settingsMessage = ""
        do {
            let response = try await withAuthorizedAccessToken { token in
                try await apiClient.restartSystem(baseURL: serverURL, token: token)
            }
            settingsMessage = response.detail
            pushNotification(title: "Raspberry Pi", detail: "Restart requested", level: .warning)
        } catch {
            settingsMessage = error.localizedDescription
        }
        isRestartingSystem = false
    }

    func presentDeviceOnboarding() {
        guard isAdmin else { return }
        isDeviceOnboardingPresented = true
        Task { await refreshOnboardingSnapshot() }
    }

    func dismissDeviceOnboarding() {
        isDeviceOnboardingPresented = false
    }

    func refreshOnboardingSnapshot() async {
        guard isAdmin else { return }
        isLoadingOnboarding = true
        do {
            let snapshot = try await withAuthorizedAccessToken { token in
                try await apiClient.refreshOnboardingDiscovery(baseURL: serverURL, token: token)
            }
            onboardingSnapshot = snapshot
        } catch {
            bannerMessage = error.localizedDescription
        }
        isLoadingOnboarding = false
    }

    func importOnboardingCandidate(
        candidateID: String,
        roomID: String,
        displayName: String,
        isFavorite: Bool
    ) async -> Bool {
        isImportingOnboardingCandidate = true
        do {
            let device = try await withAuthorizedAccessToken { token in
                try await apiClient.importOnboardingCandidate(
                    baseURL: serverURL,
                    token: token,
                    request: DeviceImportRequest(
                        candidateID: candidateID,
                        roomID: roomID,
                        displayName: displayName,
                        isVisible: true,
                        isFavorite: isFavorite,
                        capabilitiesOverride: nil
                    )
                )
            }
            pushNotification(title: device.name, detail: "Added to \(device.roomName)", level: .info)
            try? await loadInitialData()
            await refreshOnboardingSnapshot()
            isImportingOnboardingCandidate = false
            return true
        } catch {
            bannerMessage = error.localizedDescription
            isImportingOnboardingCandidate = false
            return false
        }
    }

    private func handleRealtimeEvent(event: String, payload: Data) {
        let decoder = JSONDecoder()
        switch event {
        case "snapshot":
            if let wrapped = try? decoder.decode(SnapshotPayload.self, from: payload) {
                rooms = wrapped.rooms
                saveWidgetSnapshot()
            }
        case "device.updated":
            if let updated = try? decoder.decode(Device.self, from: payload) {
                mergeDevice(updated)
                saveWidgetSnapshot()
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

    private func saveWidgetSnapshot() {
        SharedWidgetStore.save(rooms: rooms, health: healthDashboard, serverURL: serverURL)
    }

    private func previewJarvisReply(for command: String) -> String {
        let normalized = command.lowercased()
        if normalized.contains("sleep") {
            return "7h 12m, score 86. Deep sleep is up and recovery is optimal."
        }
        if normalized.contains("glucose") {
            return "Glucose is 94 mg/dL and currently in target."
        }
        if normalized.contains("gaming") && normalized.contains("off") {
            if let room = rooms.first(where: { $0.name.lowercased().contains("gaming") }) {
                Task { await setRoomState(room, isOn: false) }
            }
            return "Gaming room powered down."
        }
        if normalized.contains("warm") || normalized.contains("bedroom") {
            return "Bedroom climate request sent. It should be comfortable shortly."
        }
        return "Done. Anything else?"
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
