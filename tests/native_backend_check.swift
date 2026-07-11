import Foundation
import SQLite3

@main
struct NativeBackendCheck {
    static func main() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try Data("model_provider = \"current\"\nmodel = \"gpt-new\"\n".utf8).write(to: home.appendingPathComponent("config.toml"))
        var database: OpaquePointer?
        precondition(sqlite3_open(home.appendingPathComponent("state_5.sqlite").path, &database) == SQLITE_OK)
        defer { sqlite3_close(database) }
        precondition(sqlite3_exec(database, "CREATE TABLE threads (id TEXT PRIMARY KEY, title TEXT, cwd TEXT, model_provider TEXT, model TEXT, archived INTEGER, updated_at TEXT); INSERT INTO threads VALUES ('selected', 'Selected', '/tmp/project', 'old', 'gpt-old', 0, '1'), ('untouched', 'Untouched', '/tmp/project', 'old', 'gpt-old', 0, '2'), ('archived', 'Archived', '/tmp/project', 'old', 'gpt-old', 1, '3');", nil, nil, nil) == SQLITE_OK)
        let paths = AppPaths(codexHome: home, appHome: home.appendingPathComponent("codexhistorysync"))
        let initialThreads = try HistoryService(paths: paths).threads()
        precondition(initialThreads.threads.allSatisfy { !$0.selected })
        let result = try HistoryService(paths: paths).sync(["selected"])
        precondition(result.updatedRows == 1)
        let rows = try SQLiteDatabase(url: paths.database, readOnly: true).query("SELECT model_provider FROM threads ORDER BY id")
        precondition(rows.map { $0["model_provider"]?.string } == ["old", "current", "old"])
        let allResult = try HistoryService(paths: paths).syncAll()
        precondition(allResult.updatedRows == 3)
        let allRows = try SQLiteDatabase(url: paths.database, readOnly: true).query("SELECT model_provider FROM threads ORDER BY id")
        precondition(allRows.map { $0["model_provider"]?.string } == ["current", "current", "current"])
        let usage = AccountUsageSnapshot(primaryRemainPercent: 75, primaryResetsAt: nil, secondaryRemainPercent: 50, secondaryResetsAt: nil, capturedAt: Date())
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let encodedUsage = try encoder.encode(usage)
        precondition(!encodedUsage.isEmpty)
        _ = try decoder.decode(AccountUsageSnapshot.self, from: encodedUsage)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let displayDate = calendar.date(from: DateComponents(year: 2026, month: 7, day: 11, hour: 18, minute: 25, second: 3))!
        precondition(AppConstants.displayDateFormatter.string(from: displayDate) == "2026-07-11 18:25:03")
        print("原生后端自检通过")
    }
}
