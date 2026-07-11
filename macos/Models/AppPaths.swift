import Foundation

struct AppPaths: Sendable {
    let codexHome: URL
    let appHome: URL

    init(
        codexHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex"),
        appHome: URL? = nil
    ) {
        self.codexHome = codexHome
        self.appHome = appHome ?? codexHome.deletingLastPathComponent().appendingPathComponent(".codexhistorysync")
    }

    var config: URL { codexHome.appendingPathComponent("config.toml") }
    var database: URL { codexHome.appendingPathComponent("state_5.sqlite") }
    var sessions: URL { codexHome.appendingPathComponent("sessions") }
    var sessionIndex: URL { codexHome.appendingPathComponent("session_index.jsonl") }
    var globalState: URL { codexHome.appendingPathComponent(".codex-global-state.json") }
    var backupDirectory: URL { appHome.appendingPathComponent("history_sync_backups") }
    var auth: URL { codexHome.appendingPathComponent("auth.json") }
    var appConfig: URL { appHome.appendingPathComponent("config.json") }
    var accountBackupDirectory: URL { appHome.appendingPathComponent("account_pool_backups") }
    var profileBackup: URL { accountBackupDirectory.appendingPathComponent("codex-profile.json") }
}
