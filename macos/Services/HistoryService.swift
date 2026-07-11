import Foundation

struct HistoryService: Sendable {
    let paths: AppPaths

    func threads() throws -> ThreadResponse {
        let config = try Configuration(contentsOf: paths.config)
        let selected = try readStringSet(from: paths.selections, key: "selected_thread_ids")
        let pinned = try readStringSet(from: paths.globalState, key: "pinned-thread-ids")
        let database = try SQLiteDatabase(url: paths.database, readOnly: true)
        let columns = try threadColumns(database)
        let archived = columns.contains("archived")
        let sql = """
            SELECT id, title, cwd, model_provider, model, \(archived ? "archived" : "0 AS archived"), updated_at
            FROM threads \(archived ? "WHERE archived = 0" : "")
            ORDER BY cwd COLLATE NOCASE, updated_at DESC, id
            """
        let items = try database.query(sql).map { row in
            let id = row["id"]?.string ?? ""
            let provider = row["model_provider"]?.string ?? ""
            let model = row["model"]?.string ?? ""
            return ThreadItem(
                id: id,
                title: displayTitle(row["title"]?.string, fallback: id),
                project: row["cwd"]?.string.nonEmpty ?? AppConstants.unassignedProjectIdentifier,
                provider: provider,
                model: model,
                updatedAt: formatTimestamp(row["updated_at"]?.string ?? "0"),
                archived: row["archived"]?.bool ?? false,
                pinned: pinned.contains(id),
                selected: selected.contains(id),
                isCurrent: provider == config.provider && (config.model == nil || model == config.model)
            )
        }
        return ThreadResponse(currentProvider: config.provider, currentModel: config.model, threads: items)
    }

    func saveSelections(_ ids: Set<String>) throws -> OperationResult {
        try writeJSON(["selected_thread_ids": ids.sorted()], to: paths.selections)
        return OperationResult(selectedCount: ids.count)
    }

    func sync(_ ids: Set<String>) throws -> OperationResult {
        guard !ids.isEmpty else { throw LocalizedServiceError("error.selection.required") }
        let config = try Configuration(contentsOf: paths.config)
        let backup = BackupService(paths: paths)
        _ = try backup.create(label: "pre-selected-sync")
        let database = try SQLiteDatabase(url: paths.database)
        let columns = try threadColumns(database)
        let activeIDs = try activeIDs(in: database, requested: ids, hasArchived: columns.contains("archived"))
        let placeholders = Array(repeating: "?", count: activeIDs.count).joined(separator: ",")
        var assignments = ["model_provider = ?"]
        var bindings = [config.provider]
        if let model = config.model, columns.contains("model") { assignments.append("model = ?"); bindings.append(model) }
        bindings.append(contentsOf: activeIDs.sorted())
        let guardClause = columns.contains("archived") ? " AND archived = 0" : ""
        let updated = try database.execute(
            "UPDATE threads SET \(assignments.joined(separator: ", ")) WHERE id IN (\(placeholders))\(guardClause)",
            bindings: bindings
        )
        let sessions = SessionService(paths: paths)
        let sessionCount = try sessions.sync(ids: activeIDs, provider: config.provider, model: config.model)
        try sessions.rebuildIndex(using: database)
        _ = try saveSelections(activeIDs)
        return OperationResult(updatedRows: updated, updatedSessionFiles: sessionCount, selectedCount: activeIDs.count)
    }

    private func activeIDs(in database: SQLiteDatabase, requested: Set<String>, hasArchived: Bool) throws -> Set<String> {
        let placeholders = Array(repeating: "?", count: requested.count).joined(separator: ",")
        let rows = try database.query(
            "SELECT id FROM threads WHERE id IN (\(placeholders))\(hasArchived ? " AND archived = 0" : "")",
            bindings: requested.sorted()
        )
        return Set(rows.compactMap { $0["id"]?.string })
    }

    private func threadColumns(_ database: SQLiteDatabase) throws -> Set<String> {
        Set(try database.query("PRAGMA table_info(threads)").compactMap { $0["name"]?.string })
    }
}

private struct Configuration {
    let provider: String
    let model: String?

    init(contentsOf url: URL) throws {
        let text = try String(contentsOf: url, encoding: .utf8)
        guard let provider = text.tomlValue(for: "model_provider") else { throw LocalizedServiceError("error.config.providerMissing") }
        self.provider = provider
        model = text.tomlValue(for: "model")
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
    func tomlValue(for key: String) -> String? {
        split(whereSeparator: \Character.isNewline).lazy
            .map(String.init)
            .first { $0.trimmingCharacters(in: .whitespaces).hasPrefix("\(key) ") || $0.trimmingCharacters(in: .whitespaces).hasPrefix("\(key)=") }?
            .split(separator: "=", maxSplits: 1).last?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }
}

private func displayTitle(_ value: String?, fallback: String) -> String {
    let title = (value?.nonEmpty ?? fallback).split(whereSeparator: \Character.isWhitespace).joined(separator: " ")
    guard title.count > AppConstants.maximumTitleLength else { return title }
    return String(title.prefix(AppConstants.maximumTitleLength - 1)) + "…"
}

private func formatTimestamp(_ value: String) -> String {
    guard let timestamp = TimeInterval(value) else { return value }
    return ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: timestamp))
}

func readStringSet(from url: URL, key: String) throws -> Set<String> {
    guard FileManager.default.fileExists(atPath: url.path) else { return [] }
    let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    return Set(object?[key] as? [String] ?? [])
}

func writeJSON(_ object: Any, to url: URL) throws {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) + Data("\n".utf8)
    try data.write(to: url, options: .atomic)
}

struct LocalizedServiceError: LocalizedError {
    let localizationKey: String
    init(_ localizationKey: String) { self.localizationKey = localizationKey }
    var errorDescription: String? { localizationKey }
}
