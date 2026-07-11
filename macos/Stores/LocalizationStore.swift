import Foundation

@MainActor
final class LocalizationStore: ObservableObject {
    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "appLanguage") }
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: "appLanguage") ?? "system"
        language = AppLanguage(rawValue: saved) ?? .system
    }

    func text(_ key: String) -> String {
        L10n.text(key, language: language)
    }
}
