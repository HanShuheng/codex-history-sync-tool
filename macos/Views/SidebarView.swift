import SwiftUI

enum Workspace: Hashable {
    case history
    case backups
}

struct SidebarView: View {
    @EnvironmentObject private var localization: LocalizationStore
    @ObservedObject var store: AppStore
    @Binding var workspace: Workspace
    @Binding var project: String

    private var projects: [String] {
        Array(Set(store.response?.threads.map(\.project) ?? [])).sorted()
    }

    var body: some View {
        List {
            Section(localization.text("sidebar.manage")) {
                Label(localization.text("nav.history"), systemImage: "bubble.left.and.bubble.right")
                    .contentShape(Rectangle()).onTapGesture { workspace = .history; project = "" }
                    .listRowBackground(workspace == .history && project.isEmpty ? Color.accentColor.opacity(0.16) : Color.clear)
                Label(localization.text("nav.backups"), systemImage: "externaldrive")
                    .contentShape(Rectangle()).onTapGesture { workspace = .backups }
                    .listRowBackground(workspace == .backups ? Color.accentColor.opacity(0.16) : Color.clear)
            }
            Section(localization.text("sidebar.projects")) {
                ForEach(projects, id: \.self) { path in
                    Label(URL(fileURLWithPath: path).lastPathComponent, systemImage: "folder")
                        .contentShape(Rectangle()).onTapGesture { workspace = .history; project = path }
                        .listRowBackground(workspace == .history && project == path ? Color.accentColor.opacity(0.16) : Color.clear)
                        .help(path)
                }
            }
        }
        .navigationTitle(localization.text("app.name"))
        .listStyle(.sidebar)
    }
}
