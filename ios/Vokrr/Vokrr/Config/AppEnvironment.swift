import Foundation

enum AppEnvironment {
    static let defaultServerURL = Bundle.main.object(forInfoDictionaryKey: "VokrrDefaultServerURL") as? String
        ?? "https://api.vokrr.com"
}
