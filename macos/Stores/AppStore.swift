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
    private var selectionSaveTask: Task<Void, Never>?

    func load() { execute { [self] in
        async let threadsRequest = client.threads(), backupsRequest = client.backups()
        let (threads, backupItems) = try await (threadsRequest, backupsRequest)
        await MainActor.run {
            response = threads; backups = backupItems
            selectedIDs = Set(threads.threads.filter(\.selected).map(\.id))
        }
    } }

    func persistSelections(immediately: Bool = false) {
        selectionSaveTask?.cancel()
        let ids = selectedIDs
        selectionSaveTask = Task { [client] in
            if !immediately {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { return }
            }
            do { _ = try await client.saveSelections(ids) }
            catch { self.error = error.localizedDescription }
        }
    }

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
