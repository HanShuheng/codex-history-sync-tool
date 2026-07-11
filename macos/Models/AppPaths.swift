import Foundation

struct AppPaths: Sendable {
    let codexHome: URL

    init(codexHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")) {
        self.codexHome = codexHome
    }

    var config: URL { codexHome.appendingPathComponent("config.toml") }
    var database: URL { codexHome.appendingPathComponent("state_5.sqlite") }
    var sessions: URL { codexHome.appendingPathComponent("sessions") }
    var sessionIndex: URL { codexHome.appendingPathComponent("session_index.jsonl") }
    var selections: URL { codexHome.appendingPathComponent("history_manager_selections.json") }
    var globalState: URL { codexHome.appendingPathComponent(".codex-global-state.json") }
    var backupDirectory: URL { codexHome.appendingPathComponent("history_sync_backups") }
    var auth: URL { codexHome.appendingPathComponent("auth.json") }
    var accountPool: URL { codexHome.appendingPathComponent("account_pool.json") }
    var accountBackupDirectory: URL { codexHome.appendingPathComponent("account_pool_backups") }
}
