import Foundation

struct LocalConfig: Codable, Sendable {
    var accounts: [AccountRecord] = []
    var selectedThreadIDs = Set<String>()

    enum CodingKeys: String, CodingKey {
        case accounts
        case selectedThreadIDs = "selected_thread_ids"
    }
}
