import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var localization: LocalizationStore
    @ObservedObject var store: AppStore
    let project: String
    @State private var search = ""
    @State private var currentOnly = false
    @State private var showSyncConfirmation = false

    private var threads: [ThreadItem] {
        (store.response?.threads ?? []).filter {
            (project.isEmpty || $0.project == project) && (!currentOnly || !$0.isCurrent) &&
            (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search))
        }.sorted { left, right in
            left.pinned == right.pinned ? left.updatedAt > right.updatedAt : left.pinned
        }
    }

    var body: some View {
        VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(project.isEmpty ? localization.text("history.all") : URL(fileURLWithPath: project).lastPathComponent).font(.title2.bold())
                        Text(String(format: localization.text("history.count"), threads.count)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }.padding(.horizontal).padding(.top, 12)
                HStack {
                    TextField(localization.text("history.search"), text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 280)
                    Toggle(localization.text("history.unsyncedOnly"), isOn: $currentOnly).toggleStyle(.switch)
                    Spacer()
                    Button(String(format: localization.text("history.syncSelected"), store.selectedIDs.count)) { showSyncConfirmation = true }
                        .buttonStyle(.borderedProminent).disabled(store.selectedIDs.isEmpty)
                }.padding()
                Table(threads) {
                    TableColumn("") { item in
                        Toggle("", isOn: selectionBinding(for: item)).labelsHidden()
                    }.width(30)
                    TableColumn(localization.text("table.task")) { item in
                        HStack { if item.pinned { Image(systemName: "pin.fill").foregroundStyle(.orange) }; Text(item.title) }
                    }
                    TableColumn(localization.text("table.assignment")) { item in
                        VStack(alignment: .leading) { Text(item.provider); Text(item.model).font(.caption).foregroundStyle(.secondary) }
                    }
                    TableColumn(localization.text("table.status")) { item in
                        Text(localization.text(item.isCurrent ? "status.current" : "status.pending")).foregroundStyle(item.isCurrent ? .green : .orange)
                    }.width(90)
                    TableColumn(localization.text("table.updated")) { item in
                        Text(item.updatedAt.replacingOccurrences(of: "T", with: " "))
                    }.width(160)
                }
                .overlay(alignment: .topLeading) {
                    Button(action: toggleAll) {
                        Image(systemName: selectionIcon)
                    }
                    .buttonStyle(.plain)
                    .disabled(threads.isEmpty)
                    .help(localization.text(allVisibleSelected ? "history.deselectAll" : "history.selectAll"))
                    .padding(.leading, 16)
                    .padding(.top, 8)
                }
        }
        .alert(localization.text("sync.confirmTitle"), isPresented: $showSyncConfirmation) {
            Button(localization.text("common.cancel"), role: .cancel) {}
            Button(localization.text("common.sync"), role: .destructive) { store.syncSelected() }
        } message: { Text(String(format: localization.text("sync.confirmMessage"), store.selectedIDs.count)) }
    }

    private var allVisibleSelected: Bool {
        !threads.isEmpty && threads.allSatisfy { store.selectedIDs.contains($0.id) }
    }

    private var selectionIcon: String {
        allVisibleSelected ? "checkmark.square.fill" :
            threads.contains { store.selectedIDs.contains($0.id) } ? "minus.square.fill" : "square"
    }

    private func toggleAll() {
        let ids = Set(threads.map(\.id))
        if allVisibleSelected { store.selectedIDs.subtract(ids) }
        else { store.selectedIDs.formUnion(ids) }
        store.persistSelections()
    }

    private func selectionBinding(for item: ThreadItem) -> Binding<Bool> {
        Binding(
            get: { store.selectedIDs.contains(item.id) },
            set: { selected in
                if selected { store.selectedIDs.insert(item.id) }
                else { store.selectedIDs.remove(item.id) }
                store.persistSelections()
            }
        )
    }
}
