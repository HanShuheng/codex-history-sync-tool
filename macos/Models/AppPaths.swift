import Foundation

struct AppPaths: Sendable {
    let codexHome: URL

    var config: URL { codexHome.appendingPathComponent("config.toml") }
    var database: URL { codexHome.appendingPathComponent("state_5.sqlite") }
    var sessions: URL { codexHome.appendingPathComponent("sessions") }
    var sessionIndex: URL { codexHome.appendingPathComponent("session_index.jsonl") }
    var selections: URL { codexHome.appendingPathComponent("history_manager_selections.json") }
    var globalState: URL { codexHome.appendingPathComponent(".codex-global-state.json") }
    var backupDirectory: URL { codexHome.appendingPathComponent("history_sync_backups") }
}
