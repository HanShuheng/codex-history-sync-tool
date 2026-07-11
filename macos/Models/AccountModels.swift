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
}

struct AccountCredentials: Codable, Sendable {
    var idToken: String?
    var accessToken: String
    var refreshToken: String?
    var accountID: String?
    var workspaceID: String?
}
