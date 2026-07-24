import Foundation

@MainActor
final class AppStore: ObservableObject {
    @Published var response: ThreadResponse?
    @Published var backups: BackupResponse?
    @Published var selectedIDs = Set<String>()
    @Published var selectedBackups = UIStateStore.shared.backupSelectedNames {
        didSet { UIStateStore.shared.backupSelectedNames = selectedBackups }
    }
    @Published var busy = false
    @Published var errorKey: String?
    let client: BackendClient
    private var selectionSaveTask: Task<Void, Never>?

    init(codexHome: URL) {
        client = BackendClient(codexHome: codexHome)
    }

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
                try? await Task.sleep(nanoseconds: AppConstants.selectionSaveDelay)
                guard !Task.isCancelled else { return }
            }
            do { _ = try await client.saveSelections(ids) }
            catch { self.errorKey = Self.errorKey(for: error) }
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
            do { try await work() } catch { self.errorKey = Self.errorKey(for: error) }
            busy = false
        }
    }

    private static func errorKey(for error: Error) -> String {
        (error as? LocalizedServiceError)?.localizationKey ?? "error.unknown"
    }
}
