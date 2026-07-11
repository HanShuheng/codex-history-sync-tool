import Foundation

struct BackupService: Sendable {
    let paths: AppPaths

    func items() throws -> BackupResponse {
        guard FileManager.default.fileExists(atPath: paths.backupDirectory.path) else {
            return BackupResponse(backups: [], totalSizeBytes: 0)
        }
        let urls = try FileManager.default.contentsOfDirectory(
            at: paths.backupDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        ).filter { $0.lastPathComponent.hasPrefix("state_5.sqlite.") && $0.lastPathComponent.hasSuffix(".bak") }
        let formatter = ISO8601DateFormatter()
        let backups = try urls.map { url -> BackupItem in
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
            let size = try AppConstants.backupSuffixes.reduce(0) { total, suffix in
                let bundled = URL(fileURLWithPath: url.path + suffix)
                guard FileManager.default.fileExists(atPath: bundled.path) else { return total }
                return total + (try bundled.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
            }
            return BackupItem(
                name: url.lastPathComponent,
                path: url.path,
                modifiedAt: formatter.string(from: values.contentModificationDate ?? .distantPast),
                sizeBytes: size
            )
        }.sorted { $0.modifiedAt > $1.modifiedAt }
        return BackupResponse(backups: backups, totalSizeBytes: backups.reduce(0) { $0 + $1.sizeBytes })
    }

    func create(label: String) throws -> URL {
        try FileManager.default.createDirectory(at: paths.backupDirectory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let destination = paths.backupDirectory.appendingPathComponent("state_5.sqlite.\(label).\(formatter.string(from: Date())).bak")
        try SQLiteDatabase(url: paths.database, readOnly: true).backup(to: destination)
        if FileManager.default.fileExists(atPath: paths.sessionIndex.path) {
            try FileManager.default.copyItem(at: paths.sessionIndex, to: URL(fileURLWithPath: destination.path + ".session_index.jsonl"))
        }
        try writeJSON(
            SessionService(paths: paths).metadataSnapshot(),
            to: URL(fileURLWithPath: destination.path + ".session_meta.json")
        )
        return destination
    }

    func delete(_ names: Set<String>) throws -> OperationResult {
        let allowed = Set(try items().backups.map(\.name))
        guard names.isSubset(of: allowed) else { throw LocalizedServiceError("error.backup.invalidName") }
        var files = 0
        var bytes = 0
        for name in names {
            let database = paths.backupDirectory.appendingPathComponent(name)
            for suffix in AppConstants.backupSuffixes {
                let url = URL(fileURLWithPath: database.path + suffix)
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                bytes += try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                try FileManager.default.removeItem(at: url)
                files += 1
            }
        }
        return OperationResult(deletedBackups: names.count, deletedFiles: files, freedBytes: bytes)
    }
}
