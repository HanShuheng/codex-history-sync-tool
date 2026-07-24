import SwiftUI

struct CodexAccessView: View {
    @EnvironmentObject private var localization: LocalizationStore
    @ObservedObject var access: CodexAccessStore

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
                access.requestAccess()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(minWidth: 640, minHeight: 420)
        .padding(40)
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
