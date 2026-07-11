import Foundation

struct SessionService: Sendable {
    let paths: AppPaths

    func sync(ids: Set<String>, provider: String, model: String?) throws -> Int {
        guard FileManager.default.fileExists(atPath: paths.sessions.path) else { return 0 }
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(at: paths.sessions, includingPropertiesForKeys: keys) else { return 0 }
        var count = 0
        for case let url as URL in enumerator where url.lastPathComponent.hasPrefix("rollout-") && url.pathExtension == "jsonl" {
            var data = try Data(contentsOf: url)
            guard let newline = data.firstIndex(of: 0x0A) else { continue }
            let firstLine = data[..<newline]
            guard var item = try JSONSerialization.jsonObject(with: firstLine) as? [String: Any],
                  var payload = item["payload"] as? [String: Any],
                  let id = payload["id"] as? String, ids.contains(id) else { continue }
            payload["model_provider"] = provider
            if let model { payload["model"] = model }
            item["payload"] = payload
            let replacement = try JSONSerialization.data(withJSONObject: item, options: [.sortedKeys])
            data.replaceSubrange(..<newline, with: replacement)
            try data.write(to: url, options: .atomic)
            count += 1
        }
        return count
    }

    func rebuildIndex(using database: SQLiteDatabase) throws {
        let columns = Set(try database.query("PRAGMA table_info(threads)").compactMap { $0["name"]?.string })
        let title = columns.contains("title") ? "title" : "id AS title"
        let updated = columns.contains("updated_at") ? "updated_at" : "0 AS updated_at"
        let archived = columns.contains("archived") ? "WHERE archived = 0" : ""
        let rows = try database.query("SELECT id, \(title), \(updated) FROM threads \(archived) ORDER BY updated_at DESC, id")
        let lines = try rows.map { row in
            try JSONSerialization.data(withJSONObject: [
                "id": row["id"]?.string ?? "",
                "thread_name": row["title"]?.string ?? row["id"]?.string ?? "",
                "updated_at": formatIndexTimestamp(row["updated_at"]?.string ?? "0")
            ], options: [.sortedKeys])
        }
        var data = lines.reduce(into: Data()) { output, line in output.append(line); output.append(0x0A) }
        if data.isEmpty { data = Data() }
        try data.write(to: paths.sessionIndex, options: .atomic)
    }

    func metadataSnapshot() throws -> [[String: String]] {
        guard FileManager.default.fileExists(atPath: paths.sessions.path),
              let enumerator = FileManager.default.enumerator(at: paths.sessions, includingPropertiesForKeys: nil) else { return [] }
        return try enumerator.compactMap { element -> [String: String]? in
            guard let url = element as? URL, url.pathExtension == "jsonl", url.lastPathComponent.hasPrefix("rollout-") else { return nil }
            let data = try Data(contentsOf: url)
            let line = data.prefix { $0 != 0x0A && $0 != 0x0D }
            guard !line.isEmpty else { return nil }
            let relative = url.path.replacingOccurrences(of: paths.codexHome.path + "/", with: "")
            return ["path": relative, "first_line": String(decoding: line, as: UTF8.self)]
        }
    }
}

private func formatIndexTimestamp(_ value: String) -> String {
    guard let timestamp = TimeInterval(value) else { return value }
    return ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: timestamp))
}
