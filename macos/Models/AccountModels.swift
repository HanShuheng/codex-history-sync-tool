import Foundation

struct AccountUsageSnapshot: Codable, Hashable, Sendable {
    var primaryRemainPercent: Double?
    var primaryResetsAt: Date?
    var secondaryRemainPercent: Double?
    var secondaryResetsAt: Date?
    var capturedAt: Date
}

struct AccountRecord: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var displayName: String
    var email: String?
    var chatgptAccountID: String?
    var workspaceID: String?
    var plan: String?
    var status: String
    var usage: AccountUsageSnapshot?
    var lastRefresh: Date?
    var lastError: String?
    var isCurrent: Bool
    var credentials: AccountCredentials?
}

struct AccountCredentials: Codable, Hashable, Sendable {
    var idToken: String?
    var accessToken: String
    var refreshToken: String?
    var accountID: String?
    var workspaceID: String?
}

struct CodexProfileBackup: Codable, Sendable {
    let authJSON: String?
    let configTOML: String?

    enum CodingKeys: String, CodingKey {
        case authJSON = "auth_json"
        case configTOML = "config_toml"
    }
}
