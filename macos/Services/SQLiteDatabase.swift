import Foundation
import SQLite3

final class SQLiteDatabase {
    private var handle: OpaquePointer?

    init(url: URL, readOnly: Bool = false) throws {
        let flags = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK else {
            throw LocalizedServiceError("error.database.open")
        }
        sqlite3_busy_timeout(handle, AppConstants.databaseBusyTimeoutMilliseconds)
    }

    deinit { sqlite3_close(handle) }

    func query(_ sql: String, bindings: [String] = []) throws -> [[String: SQLiteValue]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw error() }
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        var rows: [[String: SQLiteValue]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String: SQLiteValue] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, index))
                row[name] = sqlite3_column_type(statement, index) == SQLITE_NULL
                    ? .null
                    : .text(String(cString: sqlite3_column_text(statement, index)))
            }
            rows.append(row)
        }
        guard sqlite3_errcode(handle) == SQLITE_OK || sqlite3_errcode(handle) == SQLITE_DONE else { throw error() }
        return rows
    }

    func execute(_ sql: String, bindings: [String] = []) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw error() }
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw error() }
        return Int(sqlite3_changes(handle))
    }

    func backup(to destination: URL) throws {
        var target: OpaquePointer?
        guard sqlite3_open(destination.path, &target) == SQLITE_OK else { throw LocalizedServiceError("error.backup.create") }
        defer { sqlite3_close(target) }
        guard let backup = sqlite3_backup_init(target, "main", handle, "main") else { throw error() }
        defer { sqlite3_backup_finish(backup) }
        guard sqlite3_backup_step(backup, -1) == SQLITE_DONE else { throw error() }
    }

    private func bind(_ values: [String], to statement: OpaquePointer?) throws {
        for (offset, value) in values.enumerated() {
            guard sqlite3_bind_text(statement, Int32(offset + 1), value, -1, SQLITE_TRANSIENT) == SQLITE_OK else { throw error() }
        }
    }

    private func error() -> LocalizedServiceError {
        LocalizedServiceError("error.database.operation")
    }
}

enum SQLiteValue {
    case text(String)
    case null

    var string: String { if case let .text(value) = self { return value }; return "" }
    var bool: Bool { string != "0" && !string.isEmpty }
    var int: Int { Int(string) ?? 0 }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
