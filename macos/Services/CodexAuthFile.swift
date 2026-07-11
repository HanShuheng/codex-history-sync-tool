import Foundation

enum CodexAuthFile {
    static func directJSON(credentials: AccountCredentials, accountID: String, now: Date = Date()) throws -> Data {
        let tokens: [String: Any] = [
            "id_token": credentials.idToken ?? "",
            "access_token": credentials.accessToken,
            "refresh_token": credentials.refreshToken ?? "",
            "account_id": credentials.accountID ?? accountID
        ]
        let object: [String: Any] = [
            "OPENAI_API_KEY": NSNull(),
            "tokens": tokens,
            "last_refresh": ISO8601DateFormatter().string(from: now)
        ]
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) + Data("\n".utf8)
    }
}
