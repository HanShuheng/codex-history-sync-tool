import Foundation

struct LocalConfigStore: Sendable {
    private let paths: AppPaths

    init(paths: AppPaths) { self.paths = paths }

    func load() throws -> LocalConfig {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        return try loadUnlocked()
    }

    func saveAccounts(_ accounts: [AccountRecord]) throws {
        try update { $0.accounts = accounts }
    }

    func saveSelectedThreadIDs(_ ids: Set<String>) throws {
        try update { $0.selectedThreadIDs = ids }
    }

    private func update(_ change: (inout LocalConfig) -> Void) throws {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        var config = try loadUnlocked()
        change(&config)
        try writeUnlocked(config)
    }

    private func loadUnlocked() throws -> LocalConfig {
        guard FileManager.default.fileExists(atPath: paths.appConfig.path) else { return LocalConfig() }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(LocalConfig.self, from: Data(contentsOf: paths.appConfig))
        } catch {
            throw AccountServiceError.credentialFile("本工具配置文件格式无效。")
        }
    }

    private func writeUnlocked(_ config: LocalConfig) throws {
        try FileManager.default.createDirectory(at: paths.appHome, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try (encoder.encode(config) + Data("\n".utf8)).write(to: paths.appConfig, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: paths.appConfig.path)
    }

    private static let lock = NSLock()
}
