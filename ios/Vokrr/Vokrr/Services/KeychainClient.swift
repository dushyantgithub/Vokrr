import Foundation
import Security

final class KeychainClient {
    private let service = "Vokrr.iOS"
    private let tokenKey = "authSession"

    func saveSession(_ session: AuthSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tokenKey,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    func loadSession() -> AuthSession? {
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
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tokenKey
        ]
        SecItemDelete(query as CFDictionary)
    }
}
