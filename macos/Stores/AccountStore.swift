import Foundation

@MainActor
final class AccountStore: ObservableObject {
    @Published var accounts: [AccountRecord] = []
    @Published var selectedIDs = UIStateStore.shared.accountSelectedIDs {
        didSet { UIStateStore.shared.accountSelectedIDs = selectedIDs }
    }
    @Published var busy = false
    @Published var message: String?
    @Published var error: String?
    @Published var autoSyncAfterAccountSwitch = false
    @Published var autoRestartCodexAfterAccountSwitch = false

    let service = AccountService()

    func load() {
        do {
            accounts = try service.load()
            autoSyncAfterAccountSwitch = try service.loadAutoSyncAfterAccountSwitch()
            autoRestartCodexAfterAccountSwitch = try service.loadAutoRestartCodexAfterAccountSwitch()
            markCurrent()
            WidgetSnapshotStore.save(accounts: accounts)
        }
        catch let caught { error = caught.localizedDescription }
    }

    func importCurrent() {
        execute {
            let (account, _) = try self.service.importCurrent()
            self.upsert(account)
            self.message = "已导入当前 Codex 账号。"
        }
    }

    func login() {
        execute {
            let (account, _) = try await self.service.login()
            self.upsert(account)
            self.message = "登录成功：\(account.displayName)"
            await self.refresh(account.id)
        }
    }

    func refreshSelectedOrAll() {
        let ids = selectedIDs.isEmpty ? accounts.map(\.id) : Array(selectedIDs)
        execute { for id in ids { await self.refresh(id) } }
    }

    func refreshCurrent() {
        guard let account = accounts.first(where: \.isCurrent) ?? accounts.first else {
            message = "暂无可刷新的账号。"
            return
        }
        execute { await self.refresh(account.id) }
    }

    func refreshWhenAccountsPageIsShown() {
        guard !busy else { return }
        refreshCurrent()
    }

    func setAutoSyncAfterAccountSwitch(_ enabled: Bool) {
        autoSyncAfterAccountSwitch = enabled
        do { try service.saveAutoSyncAfterAccountSwitch(enabled) }
        catch let caught { error = caught.localizedDescription }
    }

    func setAutoRestartCodexAfterAccountSwitch(_ enabled: Bool) {
        autoRestartCodexAfterAccountSwitch = enabled
        do { try service.saveAutoRestartCodexAfterAccountSwitch(enabled) }
        catch let caught { error = caught.localizedDescription }
    }

    func warmupSelectedOrAll() {
        let ids = selectedIDs.isEmpty ? accounts.map(\.id) : Array(selectedIDs)
        execute {
            var failures: [String] = []
            for id in ids {
                guard let account = self.accounts.first(where: { $0.id == id }) else { continue }
                do { self.upsert(try await self.service.warmup(account)) }
                catch { let message = error.localizedDescription; self.updateError(id, message); failures.append("\(account.displayName)（\(message)）") }
            }
            self.message = failures.isEmpty ? "预热完成。" : "预热完成，失败 \(failures.count) 个：\(failures.joined(separator: "、"))"
        }
    }

    func switchTo(_ account: AccountRecord, autoSync: Bool, autoRestartCodex: Bool) {
        execute {
            let switched = try await self.service.switchTo(account)
            var refreshed = switched
            var refreshMessage = ""
            do {
                refreshed = try await self.service.refresh(switched)
            } catch {
                refreshMessage = "额度刷新失败，请稍后手动刷新。"
            }
            self.accounts = self.accounts.map { var item = $0; item = item.id == account.id ? refreshed : item; item.isCurrent = item.id == account.id; return item }
            WidgetSnapshotStore.save(accounts: self.accounts)
            try self.service.save(self.accounts)
            try self.service.saveAutoSyncAfterAccountSwitch(autoSync)
            self.autoSyncAfterAccountSwitch = autoSync
            try self.service.saveAutoRestartCodexAfterAccountSwitch(autoRestartCodex)
            self.autoRestartCodexAfterAccountSwitch = autoRestartCodex
            var syncMessage = ""
            if autoSync {
                do {
                    let result = try self.service.syncAllHistory()
                    syncMessage = "已自动同步全部历史记录（更新 \(result.updatedRows ?? 0) 条）。"
                } catch {
                    syncMessage = "自动同步全部历史记录失败，请到历史记录页面手动同步。"
                }
            }
            var restartMessage = ""
            if autoRestartCodex {
                do {
                    restartMessage = try await self.service.restartCodexIfRunning() ? "Codex 已自动重启。" : "Codex 当前未运行，未执行重启。"
                } catch {
                    restartMessage = "Codex 自动重启失败，请手动重启。"
                }
            } else {
                restartMessage = "请重启 Codex 使新登录态生效。"
            }
            self.message = "已切换到 \(account.displayName)。\(refreshMessage)\(syncMessage)\(restartMessage)"
        }
    }

    private func refresh(_ id: String) async {
        guard let account = accounts.first(where: { $0.id == id }) else { return }
        do { upsert(try await service.refresh(account)) }
        catch { updateError(id, error.localizedDescription) }
    }

    private func upsert(_ account: AccountRecord) {
        if let index = accounts.firstIndex(where: { $0.id == account.id }) { accounts[index] = account } else { accounts.append(account) }
        WidgetSnapshotStore.save(accounts: accounts)
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
