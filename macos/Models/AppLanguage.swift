import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }

    var locale: Locale {
        switch self {
        case .system: .current
        case .english: Locale(identifier: "en_US")
        case .simplifiedChinese: Locale(identifier: "zh_Hans_CN")
        }
    }

    var displayName: String {
        switch self {
        case .system: L10n.text("language.system")
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        }
    }
}
