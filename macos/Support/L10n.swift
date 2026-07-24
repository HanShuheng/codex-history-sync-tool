import Foundation

enum L10n {
    private static let resourceBundle: Bundle = {
        #if SWIFT_PACKAGE
        let name = "CodexHistorySync_CodexHistorySync"
        if let url = Bundle.main.url(forResource: name, withExtension: "bundle"), let bundle = Bundle(url: url) {
            return bundle
        }
        let resourceURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("\(name).bundle", isDirectory: true)
        if let bundle = Bundle(url: resourceURL) { return bundle }
        #endif
        return Bundle.main
    }()

    private static let bundles: [AppLanguage: Bundle] = [AppLanguage.english, .simplifiedChinese].reduce(into: [:]) { result, language in
        guard let path = resourceBundle.path(forResource: language.rawValue.lowercased(), ofType: "lproj"),
              let bundle = Bundle(path: path) else { return }
        result[language] = bundle
    }

    static func text(_ key: String, language: AppLanguage = .system) -> String {
        let resolvedLanguage = language == .system ? systemLanguage() : language
        guard let bundle = bundles[resolvedLanguage] else {
            return resourceBundle.localizedString(forKey: key, value: key, table: nil)
        }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func systemLanguage(preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        preferredLanguages.first?.lowercased().hasPrefix("zh") == true ? .simplifiedChinese : .english
    }
}
