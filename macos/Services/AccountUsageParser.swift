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
        (try? validate(data)) != nil
    }

    static func validate(_ data: Data) throws {
        var event: String?
        var dataLines: [String] = []
        for line in String(decoding: data, as: UTF8.self).split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = String(line).trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            if line.isEmpty {
                if try process(event: event, dataLines: dataLines) { return }
                event = nil; dataLines.removeAll(); continue
            }
            if let value = line.stripPrefix("event:") { event = value.trimmingCharacters(in: .whitespaces) }
            if let value = line.stripPrefix("data:") { dataLines.append(value.trimmingCharacters(in: .whitespaces)) }
        }
        if try process(event: event, dataLines: dataLines) { return }
        throw AccountServiceError.warmupIncomplete
    }

    private static func process(event: String?, dataLines: [String]) throws -> Bool {
        if let event, isTerminal(event) { return true }
        let payload = dataLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if payload == "[DONE]" { return true }
        guard !payload.isEmpty, let object = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] else {
            if let event, isError(event) { throw AccountServiceError.warmupFailed(event) }
            return false
        }
        let type = (object["type"] as? String) ?? event
        if let type, isTerminal(type) { return true }
        if let type, isError(type) {
            let message = ((object["error"] as? [String: Any])?["message"] as? String)
                ?? (((object["response"] as? [String: Any])?["error"] as? [String: Any])?["message"] as? String)
                ?? type
            throw AccountServiceError.warmupFailed(message)
        }
        return false
    }

    private static func isTerminal(_ value: String) -> Bool {
        ["response.completed", "response.done"].contains(value.trimmingCharacters(in: .whitespaces))
    }

    private static func isError(_ value: String) -> Bool {
        ["error", "response.failed", "response.incomplete"].contains(value.trimmingCharacters(in: .whitespaces))
    }
}

private extension String {
    func stripPrefix(_ prefix: String) -> String? { hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil }
}
