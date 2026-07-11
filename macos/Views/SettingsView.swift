import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var localization: LocalizationStore

    var body: some View {
        Form {
            Picker(localization.text("settings.language"), selection: $localization.language) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
