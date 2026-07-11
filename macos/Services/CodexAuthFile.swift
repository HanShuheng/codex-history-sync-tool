import Foundation

enum CodexAuthFile {
    private static let managedProvider = "cm"

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

    static func directConfig(from content: String?) -> String {
        guard let content else { return "" }
        var output: [String] = []
        var skippingManagedTable = false
        for line in content.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let text = String(line)
            let trimmed = text.trimmingCharacters(in: CharacterSet.whitespaces)
            if trimmed.hasPrefix("[") {
                skippingManagedTable = trimmed == "[model_providers.\(managedProvider)]" || trimmed.hasPrefix("[model_providers.\(managedProvider).")
            }
            if skippingManagedTable || isManagedProviderSetting(trimmed) { continue }
            output.append(text)
        }
        return output.joined(separator: "\n")
    }

    private static func isManagedProviderSetting(_ line: String) -> Bool {
        let fields = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard fields.count == 2, fields[0] == "model_provider" else { return false }
        return fields[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"")) == managedProvider
    }
}
