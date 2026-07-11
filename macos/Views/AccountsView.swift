import SwiftUI

struct AccountsView: View {
    @EnvironmentObject private var localization: LocalizationStore
    @ObservedObject var store: AccountStore
    @State private var showImport = false
    @State private var pendingSwitch: AccountRecord?
    @State private var autoSyncAfterSwitch = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(localization.text("accounts.title")).font(.title2.bold())
                    Text(String(format: localization.text("accounts.count"), store.accounts.count)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(localization.text("accounts.import")) { showImport = true }
                Button(localization.text("accounts.login")) { store.login() }.buttonStyle(.borderedProminent)
            }
            HStack {
                Button(localization.text("accounts.refresh")) { store.refreshSelectedOrAll() }.disabled(store.accounts.isEmpty || store.busy)
                Button(localization.text("accounts.warmup")) { store.warmupSelectedOrAll() }.disabled(store.accounts.isEmpty || store.busy)
                Text(localization.text("accounts.hint")).font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            Table(store.accounts, selection: $store.selectedIDs) {
                TableColumn(localization.text("accounts.column.name")) { account in
                    VStack(alignment: .leading) {
                        HStack { Text(account.displayName); if account.isCurrent { Text(localization.text("accounts.current")).font(.caption2).foregroundStyle(.green) } }
                        Text(account.email ?? account.id).font(.caption).foregroundStyle(.secondary)
                    }
                }.width(min: 220, ideal: 280)
                TableColumn(localization.text("accounts.column.plan")) { account in Text(account.plan ?? localization.text("value.unknown")) }
                TableColumn(localization.text("accounts.column.fiveHour")) { account in usageText(account.usage?.primaryRemainPercent, reset: account.usage?.primaryResetsAt, tint: .green) }
                TableColumn(localization.text("accounts.column.sevenDay")) { account in usageText(account.usage?.secondaryRemainPercent, reset: account.usage?.secondaryResetsAt, tint: .blue) }
                TableColumn(localization.text("accounts.column.status")) { account in
                    Text(account.status == "active" ? localization.text("accounts.active") : account.status)
                        .foregroundStyle(account.status == "active" ? .green : .orange)
                        .help(account.lastError ?? "")
                }
                TableColumn(localization.text("accounts.column.action")) { account in
                    Button {
                        pendingSwitch = account
                        autoSyncAfterSwitch = store.autoSyncAfterAccountSwitch
                    } label: {
                        Label(localization.text("accounts.switch"), systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)
                    .disabled(account.isCurrent)
                }
            }
        }
        .padding(20)
        .overlay { if store.busy { ProgressView().controlSize(.large) } }
        .alert(localization.text("accounts.importTitle"), isPresented: $showImport) {
            Button(localization.text("common.cancel"), role: .cancel) {}
            Button(localization.text("accounts.import")) { store.importCurrent() }
        } message: { Text(localization.text("accounts.importMessage")) }
        .sheet(item: $pendingSwitch) { account in
            SwitchAccountSheet(account: account, autoSync: Binding(
                get: { autoSyncAfterSwitch },
                set: {
                    autoSyncAfterSwitch = $0
                    store.setAutoSyncAfterAccountSwitch($0)
                }
            )) {
                pendingSwitch = nil
            } confirm: {
                pendingSwitch = nil
                store.switchTo(account, autoSync: autoSyncAfterSwitch)
            }
        }
        .alert(localization.text("error.title"), isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button(localization.text("common.ok")) { store.error = nil }
        } message: { Text(store.error ?? "") }
        .alert(localization.text("accounts.done"), isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
            Button(localization.text("common.ok")) { store.message = nil }
        } message: { Text(store.message ?? "") }
    }

    private func usageText(_ percent: Double?, reset: Date?, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(percent.map { String(format: "%.0f%%", $0) } ?? localization.text("value.unknown"))
                Spacer(minLength: 0)
            }
            if let percent {
                ProgressView(value: max(0, min(100, percent)), total: 100)
                    .progressViewStyle(.linear)
                    .tint(tint)
            }
            if let reset { Text(localization.date(ISO8601DateFormatter().string(from: reset))).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

private struct SwitchAccountSheet: View {
    @EnvironmentObject private var localization: LocalizationStore
    let account: AccountRecord
    @Binding var autoSync: Bool
    let cancel: () -> Void
    let confirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(localization.text("accounts.switchSheetTitle"), systemImage: "person.crop.circle.badge.arrow.right")
                .font(.title3.bold())
            VStack(alignment: .leading, spacing: 3) {
                Text(account.displayName).font(.headline)
                Text(account.email ?? account.id).font(.caption).foregroundStyle(.secondary)
            }
            Text(localization.text("accounts.switchSheetMessage")).font(.callout).foregroundStyle(.secondary)
            Toggle(localization.text("accounts.autoSyncAfterSwitch"), isOn: $autoSync)
            Text(localization.text("accounts.autoSyncHelp")).font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(localization.text("common.cancel"), action: cancel)
                Button(localization.text("accounts.switch"), action: confirm).buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 430)
    }
}
