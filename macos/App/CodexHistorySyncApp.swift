import AppKit
import SwiftUI

private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct CodexHistorySyncApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var localization = LocalizationStore()

    var body: some Scene {
        WindowGroup {
            MainView().environmentObject(localization)
        }
        .defaultSize(width: 1180, height: 760)
        Settings { SettingsView().environmentObject(localization) }
    }
}
