import Foundation

@MainActor
final class CodexAccessStore: ObservableObject {
    private static let defaultCodexHome = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")

    @Published private(set) var codexHome: URL?
    @Published var error: String?

    init() {
        codexHome = Self.defaultCodexHome
    }

    func authorizeDefaultAccess() {
        codexHome = Self.defaultCodexHome
    }
}
