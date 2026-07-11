import AppKit
import SwiftUI

private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct MainView: View {
    @EnvironmentObject private var localization: LocalizationStore
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = AppStore()
    @State private var workspace = Workspace.history
    @State private var project = ""
    var body: some View {
        NavigationSplitView {
            SidebarView(store: store, workspace: $workspace, project: $project)
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        } detail: {
            Group {
                switch workspace {
                case .history: HistoryView(store: store, project: project)
                case .backups: BackupView(store: store)
                }
            }
            .navigationTitle(localization.text(workspace == .history ? "nav.history" : "nav.backups"))
        }
        .frame(minWidth: 960, minHeight: 620)
        .overlay { if store.busy { ProgressView().controlSize(.large) } }
        .toolbar {
            Picker(localization.text("settings.language"), selection: $localization.language) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language == .system ? localization.text("language.system") : language.displayName)
                        .tag(language)
                }
            }
            .pickerStyle(.menu)
            .help(localization.text("settings.language"))
        }
        .task { store.load() }
        .onChange(of: scenePhase) { phase in
            if phase == .background { store.persistSelections(immediately: true) }
        }
        .onDisappear { store.persistSelections(immediately: true) }
        .alert(localization.text("error.title"), isPresented: Binding(get: { store.errorKey != nil }, set: { if !$0 { store.errorKey = nil } })) {
            Button(localization.text("common.ok")) { store.errorKey = nil }
        } message: { Text(localization.text(store.errorKey ?? "error.unknown")) }
    }
}

@main
struct CodexHistorySyncApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var localization = LocalizationStore()

    var body: some Scene {
        WindowGroup { MainView().environmentObject(localization) }
        Settings { SettingsView().environmentObject(localization) }
    }
}
