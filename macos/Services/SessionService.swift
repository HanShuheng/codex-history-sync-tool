import Foundation

struct SessionService: Sendable {
    let paths: AppPaths

    func sync(
        ids: Set<String>,
        provider: String,
        model: String?,
        database: SQLiteDatabase,
        columns: Set<String>
    ) throws -> Int {
        guard columns.contains("rollout_path") else {
            return try syncByScanningSessions(ids: ids, provider: provider, model: model)
        }
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        let rows = try database.query(
            "SELECT id, rollout_path FROM threads WHERE id IN (\(placeholders))",
            bindings: ids.sorted()
        )
        return try rows.reduce(into: 0) { count, row in
            let path = row["rollout_path"]?.string ?? ""
            guard !path.isEmpty else { return }
            if try updateMetadata(at: URL(fileURLWithPath: path), provider: provider, model: model) {
                count += 1
            }
        }
    }

    private func syncByScanningSessions(ids: Set<String>, provider: String, model: String?) throws -> Int {
        guard FileManager.default.fileExists(atPath: paths.sessions.path) else { return 0 }
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(at: paths.sessions, includingPropertiesForKeys: keys) else { return 0 }
        var count = 0
        for case let url as URL in enumerator where url.lastPathComponent.hasPrefix("rollout-") && url.pathExtension == "jsonl" {
            let data = try Data(contentsOf: url)
            guard let newline = data.firstIndex(of: 0x0A),
                  let item = try JSONSerialization.jsonObject(with: data[..<newline]) as? [String: Any],
                  let payload = item["payload"] as? [String: Any],
                  let id = payload["id"] as? String, ids.contains(id) else { continue }
            if try updateMetadata(at: url, provider: provider, model: model) {
                count += 1
            }
        }
        return count
    }

    private func updateMetadata(at url: URL, provider: String, model: String?) throws -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        var data = try Data(contentsOf: url)
        guard let newline = data.firstIndex(of: 0x0A),
              var item = try JSONSerialization.jsonObject(with: data[..<newline]) as? [String: Any],
              var payload = item["payload"] as? [String: Any] else { return false }
        payload["model_provider"] = provider
        if let model { payload["model"] = model }
        item["payload"] = payload
        let replacement = try JSONSerialization.data(withJSONObject: item, options: [.sortedKeys])
        data.replaceSubrange(..<newline, with: replacement)
        try data.write(to: url, options: .atomic)
        return true
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
