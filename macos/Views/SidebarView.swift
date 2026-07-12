import SwiftUI

enum Workspace: String, Hashable {
    case history
    case backups
    case accounts
}

private enum SidebarSelection: Hashable {
    case history
    case backups
    case accounts
    case project(String)
}

struct SidebarView: View {
    @EnvironmentObject private var localization: LocalizationStore
    @ObservedObject var store: AppStore
    @Binding var workspace: Workspace
    @Binding var project: String

    private var projects: [String] {
        Array(Set(store.response?.threads.map(\.project) ?? [])).sorted()
    }

    private var selection: Binding<SidebarSelection?> {
        Binding(
            get: {
                if workspace == .backups { return .backups }
                if workspace == .accounts { return .accounts }
                return project.isEmpty ? .history : .project(project)
            },
            set: { selected in
                switch selected {
                case .history: workspace = .history; project = ""
                case .backups: workspace = .backups
                case .accounts: workspace = .accounts; project = ""
                case .project(let path): workspace = .history; project = path
                case nil: break
                }
            }
        )
    }

    var body: some View {
        List(selection: selection) {
            Section(localization.text("sidebar.manage")) {
                Label(localization.text("nav.history"), systemImage: "bubble.left.and.bubble.right")
                    .tag(SidebarSelection.history)
                Label(localization.text("nav.backups"), systemImage: "externaldrive")
                    .tag(SidebarSelection.backups)
                Label(localization.text("nav.accounts"), systemImage: "person.3")
                    .tag(SidebarSelection.accounts)
            }
            Section(localization.text("sidebar.projects")) {
                ForEach(projects, id: \.self) { path in
                    Label(path == AppConstants.unassignedProjectIdentifier ? localization.text("project.unassigned") : URL(fileURLWithPath: path).lastPathComponent, systemImage: "folder")
                        .tag(SidebarSelection.project(path))
                        .help(path == AppConstants.unassignedProjectIdentifier ? localization.text("project.unassigned") : path)
                }
            }
        }
        .navigationTitle(localization.text("app.name"))
        .listStyle(.sidebar)
    }
}
