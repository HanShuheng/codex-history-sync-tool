import Foundation

struct LocalConfig: Codable, Sendable {
    var accounts: [AccountRecord] = []
    var selectedThreadIDs = Set<String>()
    var autoSyncAfterAccountSwitch = false

    enum CodingKeys: String, CodingKey {
        case accounts
        case selectedThreadIDs = "selected_thread_ids"
        case autoSyncAfterAccountSwitch = "auto_sync_after_account_switch"
    }

    init(accounts: [AccountRecord] = [], selectedThreadIDs: Set<String> = [], autoSyncAfterAccountSwitch: Bool = false) {
        self.accounts = accounts
        self.selectedThreadIDs = selectedThreadIDs
        self.autoSyncAfterAccountSwitch = autoSyncAfterAccountSwitch
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accounts = try container.decodeIfPresent([AccountRecord].self, forKey: .accounts) ?? []
        selectedThreadIDs = try container.decodeIfPresent(Set<String>.self, forKey: .selectedThreadIDs) ?? []
        autoSyncAfterAccountSwitch = try container.decodeIfPresent(Bool.self, forKey: .autoSyncAfterAccountSwitch) ?? false
    }
}
