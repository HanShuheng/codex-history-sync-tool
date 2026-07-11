import Foundation

@MainActor
final class AccountStore: ObservableObject {
    @Published var accounts: [AccountRecord] = []
    @Published var selectedIDs = Set<String>()
    @Published var busy = false
    @Published var message: String?
    @Published var error: String?

    let service = AccountService()

    func load() {
        do { accounts = try service.load(); markCurrent() }
        catch let caught { error = caught.localizedDescription }
    }

    func importCurrent() {
        execute {
            let (account, credentials) = try self.service.importCurrent()
            try self.service.keychain.save(credentials, for: account.id)
            self.upsert(account)
            self.message = "已导入当前 Codex 账号。"
        }
    }

    func login() {
        execute {
            let (account, credentials) = try await self.service.login()
            try self.service.keychain.save(credentials, for: account.id)
            self.upsert(account)
            self.message = "登录成功：\(account.displayName)"
            await self.refresh(account.id)
        }
    }

    func refreshSelectedOrAll() {
        let ids = selectedIDs.isEmpty ? accounts.map(\.id) : Array(selectedIDs)
        execute { for id in ids { await self.refresh(id) } }
    }

    func warmupSelectedOrAll() {
        let ids = selectedIDs.isEmpty ? accounts.map(\.id) : Array(selectedIDs)
        execute {
            for id in ids {
                guard let account = self.accounts.first(where: { $0.id == id }) else { continue }
                do { self.upsert(try await self.service.warmup(account)) }
                catch { self.updateError(id, error.localizedDescription) }
            }
            self.message = "预热完成。"
        }
    }

    func switchTo(_ account: AccountRecord) {
        execute {
            try self.service.switchTo(account)
            self.accounts = self.accounts.map { var item = $0; item.isCurrent = item.id == account.id; return item }
            try self.service.save(self.accounts)
            self.message = "已切换到 \(account.displayName)，请重启 Codex 使新登录态生效。"
        }
    }

    private func refresh(_ id: String) async {
        guard let account = accounts.first(where: { $0.id == id }) else { return }
        do { upsert(try await service.refresh(account)) }
        catch { updateError(id, error.localizedDescription) }
    }

    private func upsert(_ account: AccountRecord) {
        if let index = accounts.firstIndex(where: { $0.id == account.id }) { accounts[index] = account } else { accounts.append(account) }
        do { try service.save(accounts) } catch let caught { error = caught.localizedDescription }
    }

    private func markCurrent() {
        let currentID = (try? service.importCurrent().0.id)
        accounts = accounts.map { var item = $0; item.isCurrent = item.id == currentID; return item }
    }

    private func updateError(_ id: String, _ message: String) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[index].lastError = message; accounts[index].status = "error"
        try? service.save(accounts)
    }

    private func execute(_ work: @escaping () async throws -> Void) {
        busy = true; error = nil
        Task {
            do { try await work() } catch { self.error = error.localizedDescription }
            self.busy = false
        }
    }
}
