import Foundation
import Security

final class KeychainClient {
    private let service = "Vokrr.iOS"
    private let tokenKey = "authSession"

    private var accessGroup: String? {
        Bundle.main.object(forInfoDictionaryKey: "VokrrKeychainAccessGroup") as? String
    }

    func saveSession(_ session: AuthSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tokenKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        var deleteQuery = query
        deleteQuery.removeValue(forKey: kSecValueData as String)
        deleteQuery.removeValue(forKey: kSecAttrAccessible as String)
        SecItemDelete(deleteQuery as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    func loadSession() -> AuthSession? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tokenKey,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        if let decoded = try? JSONDecoder().decode(AuthSession.self, from: data) {
            return decoded
        }
        if let token = String(data: data, encoding: .utf8) {
            return AuthSession(
                accessToken: token,
                refreshToken: "",
                tokenType: "Bearer",
                expiresIn: 0,
                user: SessionUser(id: "", username: "admin", isAdmin: false)
            )
        }
        return nil
    }

    func clearSession() {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tokenKey
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        SecItemDelete(query as CFDictionary)
    }
}
