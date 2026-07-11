import Foundation

enum L10n {
    private static let bundles: [AppLanguage: Bundle] = [AppLanguage.english, .simplifiedChinese].reduce(into: [:]) { result, language in
        guard let path = Bundle.module.path(forResource: language.rawValue.lowercased(), ofType: "lproj"),
              let bundle = Bundle(path: path) else { return }
        result[language] = bundle
    }

    static func text(_ key: String, language: AppLanguage = .system) -> String {
        let resolvedLanguage = language == .system ? systemLanguage() : language
        guard let bundle = bundles[resolvedLanguage] else {
            return Bundle.module.localizedString(forKey: key, value: key, table: nil)
        }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func systemLanguage(preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        preferredLanguages.first?.lowercased().hasPrefix("zh") == true ? .simplifiedChinese : .english
    }
}
