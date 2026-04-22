import Foundation
import Security

private struct StoredSession: Codable {
    let accessToken: String
    let refreshToken: String
}

final class KeychainClient {
    private let service = "Vokrr.iOS"
    private let tokenKey = "authSession"

    func saveSession(accessToken: String, refreshToken: String) {
        let payload = StoredSession(accessToken: accessToken, refreshToken: refreshToken)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tokenKey,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    func loadSession() -> (accessToken: String, refreshToken: String)? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tokenKey,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        if let decoded = try? JSONDecoder().decode(StoredSession.self, from: data) {
            return (decoded.accessToken, decoded.refreshToken)
        }
        if let token = String(data: data, encoding: .utf8) {
            return (token, "")
        }
        return nil
    }

    func clearSession() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tokenKey
        ]
        SecItemDelete(query as CFDictionary)
    }
}
