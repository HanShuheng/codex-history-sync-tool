import Foundation

enum L10n {
    static func text(_ key: String, language: AppLanguage = .system) -> String {
        guard language != .system,
              let path = Bundle.module.path(forResource: language.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return Bundle.module.localizedString(forKey: key, value: key, table: nil)
        }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
}
