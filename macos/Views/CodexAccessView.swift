import SwiftUI

struct CodexAccessView: View {
    @EnvironmentObject private var localization: LocalizationStore
    @ObservedObject var access: CodexAccessStore
    @State private var showAuthorization = true

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text(localization.text("access.title")).font(.title2.bold())
            Text(localization.text("access.message"))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
            Button(localization.text("access.choose")) {
                showAuthorization = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(minWidth: 640, minHeight: 420)
        .padding(40)
        .alert(localization.text("access.confirmTitle"), isPresented: $showAuthorization) {
            Button(localization.text("access.allow")) {
                access.authorizeDefaultAccess()
            }
            Button(localization.text("access.deny"), role: .cancel) {}
        } message: {
            Text(localization.text("access.confirmMessage"))
        }
        .alert(localization.text("error.title"), isPresented: Binding(
            get: { access.error != nil },
            set: { if !$0 { access.error = nil } }
        )) {
            Button(localization.text("common.ok")) { access.error = nil }
        } message: {
            Text(access.error ?? "")
        }
    }
}
