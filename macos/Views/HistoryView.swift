import SwiftUI

private struct SelectionColumnCenterKey: PreferenceKey {
    static var defaultValue: CGFloat? = nil

    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        if value == nil { value = nextValue() }
    }
}

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
            header
            Divider()
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
                table
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
        } message: {
            Text(String(format: localization.text("sync.confirmMessage"), store.selectedIDs.count))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(projectTitle).font(.title2.bold())
                    Text(String(format: localization.text("history.count"), threads.count))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showSyncConfirmation = true
                } label: {
                    Label(
                        String(format: localization.text("history.syncSelected"), store.selectedIDs.count),
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.selectedIDs.isEmpty || store.busy)
            }
            HStack(spacing: 12) {
                TextField(localization.text("history.search"), text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
                Toggle(localization.text("history.unsyncedOnly"), isOn: $currentOnly)
                    .toggleStyle(.switch)
                Spacer()
            }
            Text(localization.text("history.syncHint"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var table: some View {
        Table(threads) {
            TableColumn("") { item in
                Toggle("", isOn: selectionBinding(for: item)).labelsHidden()
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: SelectionColumnCenterKey.self,
                                value: proxy.frame(in: .global).midX
                            )
                        }
                    }
            }
            TableColumn(localization.text("table.task")) { item in
                HStack {
                    if item.pinned { Image(systemName: "pin.fill").foregroundStyle(.orange) }
                    Text(item.title)
                }
            }
            TableColumn(localization.text("table.assignment")) { item in
                VStack(alignment: .leading) {
                    Text(item.provider.isEmpty ? localization.text("value.empty") : item.provider)
                    Text(item.model.isEmpty ? localization.text("value.empty") : item.model)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            TableColumn(localization.text("table.status")) { item in
                Text(localization.text(item.isCurrent ? "status.current" : "status.pending"))
                    .foregroundStyle(item.isCurrent ? .green : .orange)
            }
            TableColumn(localization.text("table.updated")) { item in
                Text(localization.date(item.updatedAt))
            }
        }
        .overlayPreferenceValue(SelectionColumnCenterKey.self) { center in
            GeometryReader { proxy in
                if let center {
                    Button(action: toggleAll) {
                        Image(systemName: selectionIcon)
                    }
                    .buttonStyle(.borderless)
                    .frame(width: 30, height: 24)
                    .position(
                        x: center - proxy.frame(in: .global).minX,
                        y: 12
                    )
                    .contentShape(Rectangle())
                    .disabled(threads.isEmpty)
                    .help(selectionActionTitle)
                    .accessibilityLabel(selectionActionTitle)
                }
            }
        }
    }

    private var allVisibleSelected: Bool {
        !threads.isEmpty && threads.allSatisfy { store.selectedIDs.contains($0.id) }
    }

    private var projectTitle: String {
        if project.isEmpty { return localization.text("history.all") }
        if project == AppConstants.unassignedProjectIdentifier { return localization.text("project.unassigned") }
        return URL(fileURLWithPath: project).lastPathComponent
    }

    private var selectionActionTitle: String {
        localization.text(allVisibleSelected ? "history.deselectVisible" : "history.selectVisible")
    }

    private var selectionIcon: String {
        allVisibleSelected ? "checkmark.square.fill" :
            threads.contains { store.selectedIDs.contains($0.id) } ? "minus.square" : "square"
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
