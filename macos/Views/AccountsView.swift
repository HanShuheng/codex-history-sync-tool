import SwiftUI

struct AccountsView: View {
    @EnvironmentObject private var localization: LocalizationStore
    @ObservedObject var store: AccountStore
    @State private var showImport = false
    @State private var pendingSwitch: AccountRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if store.accounts.isEmpty {
                EmptyStateView(
                    title: localization.text("accounts.emptyTitle"),
                    message: localization.text("accounts.emptyMessage"),
                    systemImage: "person.3"
                )
            } else {
                accountTable
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom) {
            Text(String(format: localization.text("accounts.count"), store.accounts.count))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.regularMaterial)
        }
        .alert(localization.text("accounts.importTitle"), isPresented: $showImport) {
            Button(localization.text("common.cancel"), role: .cancel) {}
            Button(localization.text("accounts.import")) { store.importCurrent() }
        } message: {
            Text(localization.text("accounts.importMessage"))
        }
        .sheet(item: $pendingSwitch) { account in
            SwitchAccountSheet(account: account) {
                pendingSwitch = nil
            } confirm: {
                pendingSwitch = nil
                store.switchTo(account, autoSync: store.autoSyncAfterAccountSwitch)
            }
        }
        .alert(localization.text("error.title"), isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button(localization.text("common.ok")) { store.error = nil }
        } message: {
            Text(store.error ?? "")
        }
        .alert(localization.text("accounts.done"), isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
            Button(localization.text("common.ok")) { store.message = nil }
        } message: {
            Text(store.message ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(localization.text("accounts.headerTitle")).font(.title2.bold())
                Text(localization.text("accounts.headerMessage"))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Text(localization.text("accounts.actionsTitle"))
                    .font(.headline)
                Button {
                    showImport = true
                } label: {
                    Label(localization.text("accounts.import"), systemImage: "person.crop.circle.badge.plus")
                }
                .buttonStyle(.bordered)
                Button {
                    store.login()
                } label: {
                    Label(localization.text("accounts.login"), systemImage: "person.badge.key")
                }
                .buttonStyle(.borderedProminent)
                Button {
                    store.refreshSelectedOrAll()
                } label: {
                    Label(localization.text("accounts.refresh"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(store.accounts.isEmpty || store.busy)
                Button {
                    store.warmupSelectedOrAll()
                } label: {
                    Label(localization.text("accounts.warmup"), systemImage: "bolt.fill")
                }
                .buttonStyle(.bordered)
                .disabled(store.accounts.isEmpty || store.busy)
                Spacer()
            }
            HStack(spacing: 12) {
                Text(localization.text("accounts.actionsHint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 620, alignment: .leading)
                Spacer()
                Toggle(localization.text("accounts.autoSyncAfterSwitch"), isOn: Binding(
                    get: { store.autoSyncAfterAccountSwitch },
                    set: { store.setAutoSyncAfterAccountSwitch($0) }
                ))
                .toggleStyle(.switch)
                .help(localization.text("accounts.autoSyncHelp"))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var accountTable: some View {
        Table(store.accounts, selection: $store.selectedIDs) {
            TableColumn(localization.text("accounts.column.name")) { account in
                VStack(alignment: .leading) {
                    HStack {
                        Text(account.displayName)
                        if account.isCurrent {
                            Text(localization.text("accounts.current"))
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                    }
                    Text(account.email ?? account.id)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 180, ideal: 240, max: 420)
            TableColumn(localization.text("accounts.column.plan")) { account in
                Text(account.plan ?? localization.text("value.unknown"))
            }
            .width(min: 90, ideal: 110, max: 180)
            TableColumn(localization.text("accounts.column.fiveHour")) { account in
                usageText(account.usage?.primaryRemainPercent, reset: account.usage?.primaryResetsAt, tint: .green)
            }
            .width(min: 150, ideal: 190, max: 260)
            TableColumn(localization.text("accounts.column.sevenDay")) { account in
                usageText(account.usage?.secondaryRemainPercent, reset: account.usage?.secondaryResetsAt, tint: .blue)
            }
            .width(min: 150, ideal: 190, max: 260)
            TableColumn(localization.text("accounts.column.status")) { account in
                Text(account.status == "active" ? localization.text("accounts.active") : account.status)
                    .foregroundStyle(account.status == "active" ? .green : .orange)
                    .help(account.lastError ?? "")
            }
            .width(min: 80, ideal: 100, max: 160)
            TableColumn(localization.text("accounts.column.action")) { account in
                Button {
                    pendingSwitch = account
                } label: {
                    Label(localization.text("accounts.switch"), systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.bordered)
                .disabled(account.isCurrent)
            }
            .width(min: 90, ideal: 110, max: 160)
        }
        .frame(minWidth: 960, maxWidth: .infinity, maxHeight: .infinity)
    }

    private func usageText(_ percent: Double?, reset: Date?, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(percent.map { String(format: "%.0f%%", $0) } ?? localization.text("value.unknown"))
            if let percent {
                ProgressView(value: max(0, min(100, percent)), total: 100)
                    .progressViewStyle(.linear)
                    .tint(tint)
            }
            if let reset {
                Text(localization.date(ISO8601DateFormatter().string(from: reset)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SwitchAccountSheet: View {
    @EnvironmentObject private var localization: LocalizationStore
    let account: AccountRecord
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
            Text(localization.text("accounts.switchSheetMessage"))
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(localization.text("common.cancel"), action: cancel)
                Button(localization.text("accounts.switch"), action: confirm)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 430)
    }
}
