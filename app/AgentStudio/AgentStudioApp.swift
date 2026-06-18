import AppKit
import SwiftUI

/// AgentStudio — native macOS app to chat with Claude (plan/review) and Codex (code),
/// in single or orchestrated mode. Direct provider APIs, bring-your-own API key.
@main
struct AgentStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var updater = UpdaterController()

    var body: some Scene {
        WindowGroup {
            RootView()
                .frame(minWidth: 1040, minHeight: 640)
                .environmentObject(updater)
        }
        .defaultSize(width: 1440, height: 920)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            // Standard "Check for Updates…" item under the app menu.
            CommandGroup(after: .appInfo) {
                CheckForUpdatesButton(updater: updater)
            }
        }
    }
}

/// Persists the in-flight conversation before the app quits, so messages written within the
/// history store's debounce window aren't lost.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { @MainActor in
            await HistoryStore.shared.flush()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
