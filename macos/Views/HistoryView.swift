import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var localization: LocalizationStore
    @ObservedObject var store: AppStore
    let project: String
    @State private var search = UIStateStore.shared.historySearch
    @State private var currentOnly = UIStateStore.shared.historyCurrentOnly
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: search) { value in UIStateStore.shared.historySearch = value }
        .onChange(of: currentOnly) { value in UIStateStore.shared.historyCurrentOnly = value }
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
        HistoryTableView(
            items: threads,
            selectedIDs: $store.selectedIDs,
            taskTitle: localization.text("table.task"),
            assignmentTitle: localization.text("table.assignment"),
            statusTitle: localization.text("table.status"),
            updatedTitle: localization.text("table.updated"),
            emptyValue: localization.text("value.empty"),
            currentValue: localization.text("status.current"),
            pendingValue: localization.text("status.pending"),
            date: localization.date,
            persistSelections: { store.persistSelections() }
        )
        .frame(minWidth: 900, maxWidth: .infinity, maxHeight: .infinity)
    }

    private var projectTitle: String {
        if project.isEmpty { return localization.text("history.all") }
        if project == AppConstants.unassignedProjectIdentifier { return localization.text("project.unassigned") }
        return URL(fileURLWithPath: project).lastPathComponent
    }

}
