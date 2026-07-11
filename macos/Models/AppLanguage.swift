import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: L10n.text("language.system")
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        }
    }
}
