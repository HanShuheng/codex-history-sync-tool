import Foundation

@MainActor
final class AppStore: ObservableObject {
    @Published var response: ThreadResponse?
    @Published var backups: BackupResponse?
    @Published var selectedIDs = Set<String>()
    @Published var selectedBackups = Set<String>()
    @Published var busy = false
    @Published var error: String?
    let client = BackendClient()

    func load() { execute { [self] in
        async let threadsRequest = client.threads(), backupsRequest = client.backups()
        let (threads, backupItems) = try await (threadsRequest, backupsRequest)
        await MainActor.run {
            response = threads; backups = backupItems
            selectedIDs = Set(threads.threads.filter(\.selected).map(\.id))
        }
    } }

    func persistSelections() {
        let ids = selectedIDs
        execute { [self] in
        _ = try await client.saveSelections(ids)
    } }

    func syncSelected() {
        let ids = selectedIDs
        execute { [self] in
        _ = try await client.sync(ids)
        async let threadsRequest = client.threads(), backupsRequest = client.backups()
        let (threads, backupItems) = try await (threadsRequest, backupsRequest)
        await MainActor.run {
            response = threads; backups = backupItems
        }
    } }

    func deleteSelectedBackups() {
        let names = selectedBackups
        execute { [self] in
        _ = try await client.deleteBackups(names)
        let backupItems = try await client.backups()
        await MainActor.run {
            backups = backupItems; selectedBackups.removeAll()
        }
    } }

    private func execute(work: @escaping @Sendable () async throws -> Void) {
        busy = true
        Task {
            do { try await work() } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}
