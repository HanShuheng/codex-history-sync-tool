import Foundation

enum AppConstants {
    static let databaseBusyTimeoutMilliseconds: Int32 = 30_000
    static let selectionSaveDelay: UInt64 = 3_000_000_000
    static let maximumTitleLength = 240
    static let unassignedProjectIdentifier = "__unassigned_project__"
    static let backupSuffixes = ["", ".session_index.jsonl", ".session_meta.json"]
    static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}
