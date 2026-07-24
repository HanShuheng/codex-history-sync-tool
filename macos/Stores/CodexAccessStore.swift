import Foundation

@MainActor
final class CodexAccessStore: ObservableObject {
    private static let authorizationKey = "codexHomeAuthorizationConfirmed"
    private static let defaultCodexHome = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")

    @Published private(set) var codexHome: URL?
    @Published var error: String?

    init() {
        codexHome = UserDefaults.standard.bool(forKey: Self.authorizationKey) && Self.hasCodexData
            ? Self.defaultCodexHome
            : nil
    }

    func authorizeDefaultAccess() {
        guard Self.hasCodexData else {
            error = "未找到默认 Codex 数据目录 ~/.codex。"
            return
        }
        UserDefaults.standard.set(true, forKey: Self.authorizationKey)
        codexHome = Self.defaultCodexHome
    }

    private static var hasCodexData: Bool {
        FileManager.default.fileExists(atPath: defaultCodexHome.appendingPathComponent("state_5.sqlite").path)
            || FileManager.default.fileExists(atPath: defaultCodexHome.appendingPathComponent("sqlite/state_5.sqlite").path)
    }
}
