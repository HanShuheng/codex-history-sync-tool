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
            if store.response == nil {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if threads.isEmpty {
                EmptyStateView(
                    title: localization.text("history.emptyTitle"),
                    message: localization.text("history.emptyMessage"),
                    systemImage: "bubble.left.and.bubble.right"
                )
            } else {
                Table(threads) {
                    TableColumn("") { item in
                        Toggle("", isOn: selectionBinding(for: item)).labelsHidden()
                    }.width(30)
                    TableColumn(localization.text("table.task")) { item in
                        HStack { if item.pinned { Image(systemName: "pin.fill").foregroundStyle(.orange) }; Text(item.title) }
                    }
                    TableColumn(localization.text("table.assignment")) { item in
                        VStack(alignment: .leading) {
                            Text(item.provider.isEmpty ? localization.text("value.empty") : item.provider)
                            Text(item.model.isEmpty ? localization.text("value.empty") : item.model).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    TableColumn(localization.text("table.status")) { item in
                        Text(localization.text(item.isCurrent ? "status.current" : "status.pending")).foregroundStyle(item.isCurrent ? .green : .orange)
                    }.width(90)
                    TableColumn(localization.text("table.updated")) { item in
                        Text(localization.date(item.updatedAt))
                    }.width(160)
                }
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: localization.text("history.search"))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Toggle(localization.text("history.unsyncedOnly"), isOn: $currentOnly)
                    .toggleStyle(.switch)
                Button(action: toggleAll) {
                    Image(systemName: selectionIcon)
                }
                .disabled(threads.isEmpty)
                .help(localization.text(allVisibleSelected ? "history.deselectAll" : "history.selectAll"))
                .accessibilityLabel(localization.text(allVisibleSelected ? "history.deselectAll" : "history.selectAll"))
                Button(String(format: localization.text("history.syncSelected"), store.selectedIDs.count)) {
                    showSyncConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.selectedIDs.isEmpty || store.busy)
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text(projectTitle).font(.headline)
                Spacer()
                Text(String(format: localization.text("history.count"), threads.count))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.regularMaterial)
        }
        .alert(localization.text("sync.confirmTitle"), isPresented: $showSyncConfirmation) {
            Button(localization.text("common.cancel"), role: .cancel) {}
            Button(localization.text("common.sync"), role: .destructive) { store.syncSelected() }
        } message: { Text(String(format: localization.text("sync.confirmMessage"), store.selectedIDs.count)) }
    }

    private var allVisibleSelected: Bool {
        !threads.isEmpty && threads.allSatisfy { store.selectedIDs.contains($0.id) }
    }

    private var projectTitle: String {
        if project.isEmpty { return localization.text("history.all") }
        if project == AppConstants.unassignedProjectIdentifier { return localization.text("project.unassigned") }
        return URL(fileURLWithPath: project).lastPathComponent
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
