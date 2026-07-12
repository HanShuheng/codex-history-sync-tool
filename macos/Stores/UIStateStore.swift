import AppKit
import Foundation

final class UIStateStore {
    static let shared = UIStateStore()

    private let defaults = UserDefaults.standard
    private let historyColumnWidthsKey = "historyColumnWidths"

    var workspace: String {
        get { defaults.string(forKey: "workspace") ?? "history" }
        set { defaults.set(newValue, forKey: "workspace") }
    }

    var project: String {
        get { defaults.string(forKey: "project") ?? "" }
        set { defaults.set(newValue, forKey: "project") }
    }

    var historySearch: String {
        get { defaults.string(forKey: "historySearch") ?? "" }
        set { defaults.set(newValue, forKey: "historySearch") }
    }

    var historyCurrentOnly: Bool {
        get { defaults.bool(forKey: "historyCurrentOnly") }
        set { defaults.set(newValue, forKey: "historyCurrentOnly") }
    }

    var accountSelectedIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: "accountSelectedIDs") ?? []) }
        set { defaults.set(Array(newValue), forKey: "accountSelectedIDs") }
    }

    var backupSelectedNames: Set<String> {
        get { Set(defaults.stringArray(forKey: "backupSelectedNames") ?? []) }
        set { defaults.set(Array(newValue), forKey: "backupSelectedNames") }
    }

    var historyColumnWidths: [String: CGFloat] {
        get {
            guard let data = defaults.data(forKey: historyColumnWidthsKey),
                  let values = try? JSONDecoder().decode([String: Double].self, from: data) else { return [:] }
            return values.mapValues { CGFloat($0) }
        }
        set {
            let values = newValue.mapValues(Double.init)
            if let data = try? JSONEncoder().encode(values) { defaults.set(data, forKey: historyColumnWidthsKey) }
        }
    }

    func saveWindowFrame(_ frame: NSRect) {
        defaults.set(NSStringFromRect(frame), forKey: "windowFrame")
    }

    func restoreWindowFrame() -> NSRect? {
        guard let value = defaults.string(forKey: "windowFrame") else { return nil }
        return NSRectFromString(value)
    }
}
