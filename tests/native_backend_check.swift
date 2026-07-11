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
        precondition(sqlite3_exec(database, "CREATE TABLE threads (id TEXT PRIMARY KEY, model_provider TEXT, model TEXT, archived INTEGER); INSERT INTO threads VALUES ('selected', 'old', 'gpt-old', 0), ('untouched', 'old', 'gpt-old', 0);", nil, nil, nil) == SQLITE_OK)
        let paths = AppPaths(codexHome: home)
        let result = try HistoryService(paths: paths).sync(["selected"])
        precondition(result.updatedRows == 1)
        let rows = try SQLiteDatabase(url: paths.database, readOnly: true).query("SELECT model_provider FROM threads ORDER BY id")
        precondition(rows.map { $0["model_provider"]?.string } == ["current", "old"])
        let usage = AccountUsageSnapshot(primaryRemainPercent: 75, primaryResetsAt: nil, secondaryRemainPercent: 50, secondaryResetsAt: nil, capturedAt: Date())
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let encodedUsage = try encoder.encode(usage)
        precondition(!encodedUsage.isEmpty)
        _ = try decoder.decode(AccountUsageSnapshot.self, from: encodedUsage)
        print("原生后端自检通过")
    }
}
