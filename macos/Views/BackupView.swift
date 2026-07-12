import SwiftUI

struct BackupView: View {
    @EnvironmentObject private var localization: LocalizationStore
    @ObservedObject var store: AppStore
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if store.backups == nil {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.backups?.backups.isEmpty == true {
                EmptyStateView(
                    title: localization.text("backup.emptyTitle"),
                    message: localization.text("backup.emptyMessage"),
                    systemImage: "externaldrive"
                )
            } else {
                backupTable
            }
        }
        .alert(localization.text("backup.deleteTitle"), isPresented: $confirmDelete) {
            Button(localization.text("common.cancel"), role: .cancel) {}
            Button(localization.text("common.delete"), role: .destructive) { store.deleteSelectedBackups() }
        } message: {
            Text(localization.text("backup.deleteMessage"))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(localization.text("backup.headerTitle")).font(.title2.bold())
                Text(localization.text("backup.headerMessage"))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Text(summary).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Button {
                    store.client.openBackups()
                } label: {
                    Label(localization.text("backup.openFolder"), systemImage: "folder")
                }
                .buttonStyle(.bordered)
                Button {
                    confirmDelete = true
                } label: {
                    Label(
                        String(format: localization.text("backup.deleteSelected"), store.selectedBackups.count),
                        systemImage: "trash"
                    )
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(store.selectedBackups.isEmpty || store.busy)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var summary: String {
        let count = store.backups?.backups.count ?? 0
        let bytes = Int64(store.backups?.totalSizeBytes ?? 0)
        return String(format: localization.text("backup.summary"), count, localization.bytes(bytes))
    }

    private var backupTable: some View {
        Table(store.backups?.backups ?? []) {
            TableColumn("") { item in
                Toggle("", isOn: binding(for: item)).labelsHidden()
            }
            TableColumn(localization.text("backup.column.name"), value: \.name)
            TableColumn(localization.text("backup.column.time")) { item in
                Text(localization.date(item.modifiedAt))
            }
            TableColumn(localization.text("backup.column.size")) { item in
                Text(localization.bytes(Int64(item.sizeBytes)))
            }
        }
    }

    private func binding(for item: BackupItem) -> Binding<Bool> {
        Binding(
            get: { store.selectedBackups.contains(item.name) },
            set: { selected in
                if selected { store.selectedBackups.insert(item.name) }
                else { store.selectedBackups.remove(item.name) }
            }
        )
    }
}
