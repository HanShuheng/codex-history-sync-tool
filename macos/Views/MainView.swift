import SwiftUI

struct MainView: View {
    @EnvironmentObject private var localization: LocalizationStore
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = AppStore()
    @ObservedObject var accountStore: AccountStore
    @State private var workspace = Workspace(rawValue: UIStateStore.shared.workspace) ?? .history
    @State private var project = UIStateStore.shared.project

    private var detailTitle: String {
        switch workspace {
        case .history: localization.text("nav.history")
        case .backups: localization.text("nav.backups")
        case .accounts: localization.text("nav.accounts")
        }
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store, workspace: $workspace, project: $project)
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        } detail: {
            detail
                .navigationTitle(detailTitle)
        }
        .frame(minWidth: 960, minHeight: 620)
        .toolbar {
            ToolbarItem {
                Picker(localization.text("settings.language"), selection: $localization.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .pickerStyle(.menu)
                .help(localization.text("settings.language"))
            }
        }
        .overlay(alignment: .topTrailing) {
            if store.busy || accountStore.busy {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, 16)
                    .padding(.top, 12)
                    .allowsHitTesting(false)
            }
        }
        .task {
            store.load()
            accountStore.load()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background { store.persistSelections(immediately: true) }
        }
        .onChange(of: workspace) { value in UIStateStore.shared.workspace = value.rawValue }
        .onChange(of: project) { value in UIStateStore.shared.project = value }
        .onDisappear { store.persistSelections(immediately: true) }
        .alert(localization.text("error.title"), isPresented: Binding(get: { store.errorKey != nil }, set: { if !$0 { store.errorKey = nil } })) {
            Button(localization.text("common.ok")) { store.errorKey = nil }
        } message: {
            Text(localization.text(store.errorKey ?? "error.unknown"))
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch workspace {
        case .history: HistoryView(store: store, project: project)
        case .backups: BackupView(store: store)
        case .accounts: AccountsView(store: accountStore)
        }
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
