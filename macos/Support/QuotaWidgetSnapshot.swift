import Foundation

struct WidgetQuotaSnapshot: Codable, Sendable {
    let displayName: String
    let plan: String?
    let primaryRemainPercent: Double?
    let primaryResetsAt: Date?
    let secondaryRemainPercent: Double?
    let secondaryResetsAt: Date?
    let capturedAt: Date?
    let status: String
    let lastError: String?
}

enum WidgetSnapshotStore {
    static let appGroup = "group.com.hanshuheng.CodexHistorySync"

    static func save(_ snapshot: WidgetQuotaSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot), let url = url() else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    static func load() -> WidgetQuotaSnapshot? {
        guard let url = url(), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetQuotaSnapshot.self, from: data)
    }

    private static func url() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?.appendingPathComponent("quota-widget.json")
    }
}
