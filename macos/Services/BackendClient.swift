import AppKit
import Foundation

struct BackendClient: Sendable {
    private let root: URL
    init() {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        root = executable.deletingLastPathComponent().deletingLastPathComponent()
    }

    func threads() async throws -> ThreadResponse { try await background(["threads"], as: ThreadResponse.self) }
    func backups() async throws -> BackupResponse { try await background(["backups"], as: BackupResponse.self) }
    func saveSelections(_ ids: Set<String>) async throws -> OperationResult {
        try await background(["save-selections", "--ids", ids.sorted().joined(separator: ",")], as: OperationResult.self)
    }
    func sync(_ ids: Set<String>) async throws -> OperationResult {
        try await background(["sync-selected", "--ids", ids.sorted().joined(separator: ",")], as: OperationResult.self)
    }
    func deleteBackups(_ names: Set<String>) async throws -> OperationResult {
        try await background(["delete-backups", "--names", names.sorted().joined(separator: ",")], as: OperationResult.self)
    }

    private func background<T: Decodable & Sendable>(_ arguments: [String], as type: T.Type) async throws -> T {
        try await Task.detached { try run(arguments, as: type) }.value
    }
    func openBackups() {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/history_sync_backups")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    private func run<T: Decodable>(_ arguments: [String], as type: T.Type) throws -> T {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", root.appendingPathComponent("history_manager.py").path] + arguments
        process.environment = ProcessInfo.processInfo.environment.merging(["PYTHONDONTWRITEBYTECODE": "1"]) { _, new in new }
        process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        // 先持续排空管道，再等待退出；大量线程 JSON 不会堵满管道造成死锁。
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let text = (try? JSONDecoder().decode(ErrorResult.self, from: data).error) ?? "后端执行失败"
            throw NSError(domain: "CodexHistorySync", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: text])
        }
        return try JSONDecoder().decode(type, from: data)
    }
}
