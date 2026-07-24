import AppKit
import SwiftUI

private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: nil, queue: .main) { notification in
            if let window = notification.object as? NSWindow { UIStateStore.shared.saveWindowFrame(window.frame) }
        }
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first else { return }
            guard var frame = UIStateStore.shared.restoreWindowFrame(),
                  frame.width >= 800,
                  frame.height >= 600 else {
                window.setContentSize(NSSize(width: 1200, height: 800))
                window.center()
                UIStateStore.shared.saveWindowFrame(window.frame)
                return
            }
            let screen = NSScreen.screens.first { $0.visibleFrame.intersects(frame) } ?? NSScreen.main
            if let visibleFrame = screen?.visibleFrame {
                frame.origin.x = max(visibleFrame.minX, min(frame.origin.x, visibleFrame.maxX - frame.width))
                frame.origin.y = max(visibleFrame.minY, min(frame.origin.y, visibleFrame.maxY - frame.height))
            }
            window.setFrame(frame, display: true)
        }
    }
}

@main
struct CodexHistorySyncApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var localization = LocalizationStore()
    @StateObject private var codexAccess = CodexAccessStore()

    var body: some Scene {
        WindowGroup {
            Group {
                if let codexHome = codexAccess.codexHome {
                    MainView(codexHome: codexHome)
                } else {
                    CodexAccessView(access: codexAccess)
                }
            }
            .environmentObject(localization)
        }
        .defaultSize(width: 1200, height: 800)
        Settings { SettingsView().environmentObject(localization) }
    }
}
