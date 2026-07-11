import AppKit
import Foundation

struct BackendClient: Sendable {
    private let paths: AppPaths

    init(codexHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")) {
        paths = AppPaths(codexHome: codexHome)
    }

    func threads() async throws -> ThreadResponse {
        try await detached { try HistoryService(paths: paths).threads() }
    }

    func backups() async throws -> BackupResponse {
        try await detached { try BackupService(paths: paths).items() }
    }

    func saveSelections(_ ids: Set<String>) async throws -> OperationResult {
        try await detached { try HistoryService(paths: paths).saveSelections(ids) }
    }

    func sync(_ ids: Set<String>) async throws -> OperationResult {
        try await detached { try HistoryService(paths: paths).sync(ids) }
    }

    func deleteBackups(_ names: Set<String>) async throws -> OperationResult {
        try await detached { try BackupService(paths: paths).delete(names) }
    }

    func openBackups() {
        try? FileManager.default.createDirectory(at: paths.backupDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(paths.backupDirectory)
    }

    private func detached<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await Task.detached(operation: work).value
    }
}
