import Foundation

enum AppEnvironment {
    static let defaultServerURL = Bundle.main.object(forInfoDictionaryKey: "QuantumHomeDefaultServerURL") as? String
        ?? "http://quantum-home.local:8080"
}
