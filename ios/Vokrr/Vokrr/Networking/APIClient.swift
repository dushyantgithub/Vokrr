import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case unauthorized
    case server(String)
    case decoding
    case unreachable

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The server address is invalid."
        case .unauthorized:
            return "Your session expired. Sign in again."
        case .server(let message):
            return message
        case .decoding:
            return "The server returned an unexpected response."
        case .unreachable:
            return "The Vokrr backend could not be reached."
        }
    }
}

final class APIClient {
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        session = URLSession(configuration: configuration)
    }

    func normalizeServerURL(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return "http://\(trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/")))"
    }

    func websocketURL(baseURL: String, token: String) throws -> URL {
        let normalized = normalizeServerURL(baseURL)
        guard var components = URLComponents(string: normalized) else {
            throw APIError.invalidURL
        }
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path = "/ws"
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        guard let url = components.url else {
            throw APIError.invalidURL
        }
        return url
    }

    func login(baseURL: String, username: String, password: String) async throws -> AuthSession {
        struct LoginRequest: Encodable {
            let username: String
            let password: String
        }

        return try await send(
            path: "/api/auth/login",
            baseURL: baseURL,
            method: "POST",
            token: nil,
            body: LoginRequest(username: username, password: password)
        )
    }

    func refreshSession(baseURL: String, refreshToken: String) async throws -> AuthSession {
        struct RefreshRequest: Encodable {
            let refreshToken: String

            enum CodingKeys: String, CodingKey {
                case refreshToken = "refresh_token"
            }
        }

        return try await send(
            path: "/api/auth/refresh",
            baseURL: baseURL,
            method: "POST",
            token: nil,
            body: RefreshRequest(refreshToken: refreshToken)
        )
    }

    func fetchHealth(baseURL: String) async throws -> HealthResponse {
        try await send(path: "/api/system/health", baseURL: baseURL, token: nil)
    }

    func fetchRooms(baseURL: String, token: String) async throws -> [Room] {
        try await send(path: "/api/rooms", baseURL: baseURL, token: token)
    }

    func fetchScenes(baseURL: String, token: String) async throws -> [Routine] {
        try await send(path: "/api/scenes", baseURL: baseURL, token: token)
    }

    func setRoomState(baseURL: String, token: String, roomID: String, isOn: Bool) async throws -> Room {
        try await send(
            path: "/api/rooms/\(roomID)/set",
            baseURL: baseURL,
            method: "POST",
            token: token,
            body: RoomSetRequest(state: isOn)
        )
    }

    func toggleDevice(baseURL: String, token: String, deviceID: String) async throws -> Device {
        try await send(
            path: "/api/devices/\(deviceID)/toggle",
            baseURL: baseURL,
            method: "POST",
            token: token
        )
    }

    func setDevice(baseURL: String, token: String, deviceID: String, request: DeviceSetRequest) async throws -> Device {
        try await send(
            path: "/api/devices/\(deviceID)/set",
            baseURL: baseURL,
            method: "POST",
            token: token,
            body: request
        )
    }

    func runScene(baseURL: String, token: String, sceneID: String) async throws -> SceneRunResponse {
        try await send(
            path: "/api/scenes/\(sceneID)/run",
            baseURL: baseURL,
            method: "POST",
            token: token
        )
    }

    func logout(baseURL: String, refreshToken: String, accessToken: String) async throws {
        struct LogoutRequest: Encodable {
            let refreshToken: String

            enum CodingKeys: String, CodingKey {
                case refreshToken = "refresh_token"
            }
        }

        let _: EmptyResponse = try await send(
            path: "/api/auth/logout",
            baseURL: baseURL,
            method: "POST",
            token: accessToken,
            body: LogoutRequest(refreshToken: refreshToken)
        )
    }

    private func send<Response: Decodable>(
        path: String,
        baseURL: String,
        method: String = "GET",
        token: String?,
        body: Encodable? = nil
    ) async throws -> Response {
        guard let url = URL(string: normalizeServerURL(baseURL) + path) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = try encoder.encode(AnyEncodable(body))
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.unreachable
            }
            switch http.statusCode {
            case 200 ..< 300:
                if data.isEmpty, Response.self == EmptyResponse.self {
                    return EmptyResponse() as! Response
                }
                do {
                    return try decoder.decode(Response.self, from: data)
                } catch {
                    throw APIError.decoding
                }
            case 401:
                throw APIError.unauthorized
            default:
                let detail = (try? decoder.decode(ServerErrorResponse.self, from: data).detail) ?? "The request failed."
                throw APIError.server(detail)
            }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.unreachable
        }
    }
}

private struct ServerErrorResponse: Decodable {
    let detail: String
}

private struct EmptyResponse: Decodable {}

private struct AnyEncodable: Encodable {
    private let encodeClosure: (Encoder) throws -> Void

    init(_ wrapped: Encodable) {
        encodeClosure = wrapped.encode
    }

    func encode(to encoder: Encoder) throws {
        try encodeClosure(encoder)
    }
}
