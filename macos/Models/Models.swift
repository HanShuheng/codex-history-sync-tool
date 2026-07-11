import Foundation

struct ThreadItem: Codable, Identifiable, Hashable, Sendable {
    let id, title, project, provider, model, updatedAt: String
    let archived, pinned, selected, isCurrent: Bool
    enum CodingKeys: String, CodingKey {
        case id, title, project, provider, model, archived, pinned, selected
        case updatedAt = "updated_at", isCurrent = "is_current"
    }
}

struct ThreadResponse: Codable, Sendable {
    let currentProvider: String
    let currentModel: String?
    let threads: [ThreadItem]
    enum CodingKeys: String, CodingKey {
        case currentProvider = "current_provider", currentModel = "current_model", threads
    }
}

struct BackupItem: Codable, Identifiable, Hashable, Sendable {
    let name, path, modifiedAt: String
    let sizeBytes: Int
    var id: String { name }
    enum CodingKeys: String, CodingKey { case name, path, modifiedAt = "modified_at", sizeBytes = "size_bytes" }
}

struct BackupResponse: Codable, Sendable {
    let backups: [BackupItem]
    let totalSizeBytes: Int
    enum CodingKeys: String, CodingKey { case backups, totalSizeBytes = "total_size_bytes" }
}

struct OperationResult: Codable, Sendable {
    let updatedRows, updatedSessionFiles, selectedCount: Int?
    let deletedBackups, deletedFiles, freedBytes: Int?
    enum CodingKeys: String, CodingKey {
        case updatedRows = "updated_rows", updatedSessionFiles = "updated_session_files", selectedCount = "selected_count"
        case deletedBackups = "deleted_backups", deletedFiles = "deleted_files", freedBytes = "freed_bytes"
    }
}

struct ErrorResult: Codable, Sendable { let error: String }
