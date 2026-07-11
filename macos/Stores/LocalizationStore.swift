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

    func date(_ value: String) -> String {
        guard let date = try? Date.ISO8601FormatStyle().parse(value) else { return value }
        return AppConstants.displayDateFormatter.string(from: date)
    }

    func bytes(_ value: Int64) -> String {
        value.formatted(.byteCount(style: .file).locale(language.locale))
    }
}
