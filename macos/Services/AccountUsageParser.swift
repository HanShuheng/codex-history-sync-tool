import Foundation

enum AccountUsageParser {
    static func snapshot(from data: Data, capturedAt: Date = Date()) throws -> AccountUsageSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AccountServiceError.invalidUsageResponse }
        let rate = root["rate_limit"] as? [String: Any]
        let primary = window(rate?["primary_window"] as? [String: Any])
        let secondary = window(rate?["secondary_window"] as? [String: Any])
        return AccountUsageSnapshot(primaryRemainPercent: primary.remain, primaryResetsAt: primary.reset, secondaryRemainPercent: secondary.remain, secondaryResetsAt: secondary.reset, capturedAt: capturedAt)
    }

    private static func window(_ value: [String: Any]?) -> (remain: Double?, reset: Date?) {
        let used = number(value?["used_percent"])
        let reset = number(value?["reset_at"]).map(Date.init(timeIntervalSince1970:))
        return (used.map { max(0, min(100, 100 - $0)) }, reset)
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }
}

enum WarmupResponseParser {
    static func isComplete(_ data: Data) -> Bool {
        String(decoding: data, as: UTF8.self).contains("response.completed")
    }
}
