import AppKit
import Foundation

@MainActor
final class CodexAccessStore: ObservableObject {
    private static let bookmarkKey = "codexHomeBookmark"

    @Published private(set) var codexHome: URL?
    @Published var error: String?

    init() {
        codexHome = Self.resolveBookmark()
    }

    func requestAccess() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        panel.showsHiddenFiles = true
        panel.prompt = "选择"
        panel.message = "请选择 Codex 数据目录 ~/.codex"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard url.lastPathComponent == ".codex" else {
            error = "请选择 ~/.codex 文件夹。"
            return
        }
        guard FileManager.default.fileExists(atPath: url.appendingPathComponent("state_5.sqlite").path)
                || FileManager.default.fileExists(atPath: url.appendingPathComponent("sqlite/state_5.sqlite").path) else {
            error = "所选文件夹不是有效的 Codex 数据目录。"
            return
        }
        do {
            let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
            guard url.startAccessingSecurityScopedResource() else {
                error = "无法获得 Codex 数据目录访问权限。"
                return
            }
            codexHome = url
        } catch {
            self.error = "无法保存 Codex 数据目录权限：\(error.localizedDescription)"
        }
    }

    private static func resolveBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ), url.startAccessingSecurityScopedResource() else { return nil }
        if stale, let refreshed = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(refreshed, forKey: bookmarkKey)
        }
        return url
    }
}
