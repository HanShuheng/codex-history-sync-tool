import SwiftUI

struct BackupView: View {
    @EnvironmentObject private var localization: LocalizationStore
    @ObservedObject var store: AppStore
    @State private var confirmDelete = false
    private let formatter = ByteCountFormatter()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            backupTable
        }.padding(20)
        .alert(localization.text("backup.deleteTitle"), isPresented: $confirmDelete) {
            Button(localization.text("common.cancel"), role: .cancel) {}
            Button(localization.text("common.delete"), role: .destructive) { store.deleteSelectedBackups() }
        } message: { Text(localization.text("backup.deleteMessage")) }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(localization.text("backup.title")).font(.title.bold())
                Text(summary).foregroundStyle(.secondary)
            }
            Spacer()
            Button(localization.text("backup.openFolder")) { store.client.openBackups() }
            Button(String(format: localization.text("backup.deleteSelected"), store.selectedBackups.count), role: .destructive) { confirmDelete = true }
                .disabled(store.selectedBackups.isEmpty)
        }
    }

    private var summary: String {
        let count = store.backups?.backups.count ?? 0
        let bytes = Int64(store.backups?.totalSizeBytes ?? 0)
        return String(format: localization.text("backup.summary"), count, formatter.string(fromByteCount: bytes))
    }

    private var backupTable: some View {
        Table(store.backups?.backups ?? []) {
            TableColumn("") { item in
                Toggle("", isOn: binding(for: item)).labelsHidden()
            }.width(30)
            TableColumn(localization.text("backup.column.name"), value: \.name)
            TableColumn(localization.text("backup.column.time"), value: \.modifiedAt).width(170)
            TableColumn(localization.text("backup.column.size")) { item in Text(formatter.string(fromByteCount: Int64(item.sizeBytes))) }.width(100)
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
