import Foundation

enum AppEnvironment {
    static let defaultServerURL = Bundle.main.object(forInfoDictionaryKey: "QuantumHomeDefaultServerURL") as? String
        ?? "https://api.quantum-home.example"
}
