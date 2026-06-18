import Combine
import Sparkle
import SwiftUI

/// Wraps Sparkle's standard updater for in-app auto-update (Developer ID distribution).
///
/// Sparkle only works on a properly **signed + notarized** build that carries a real EdDSA
/// public key (`SUPublicEDKey`). Until that's set up — e.g. local dev builds, or before you run
/// Sparkle's `generate_keys` — we DON'T start the updater and hide the "Check for Updates" UI,
/// so an unconfigured build never shows Sparkle's scary "updater failed to start" dialog.
@MainActor
final class UpdaterController: ObservableObject {
    /// True once a real Sparkle public key is present (not empty / not the placeholder).
    let isConfigured: Bool
    private let controller: SPUStandardUpdaterController?
    /// Whether a manual check can run right now (false while a check/install is in flight).
    @Published var canCheck = false

    init() {
        let key = (Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String) ?? ""
        let underTest = NSClassFromString("XCTestCase") != nil   // don't hit the network during tests
        isConfigured = !key.isEmpty && !key.hasPrefix("REPLACE_")

        guard isConfigured, !underTest else { controller = nil; return }
        let c = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        controller = c
        c.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheck)
    }

    func checkForUpdates() { controller?.updater.checkForUpdates() }
}

/// Menu/Settings "Check for Updates…" action. Renders nothing until Sparkle is configured.
struct CheckForUpdatesButton: View {
    @ObservedObject var updater: UpdaterController
    @Environment(\.lang) private var lang

    var body: some View {
        if updater.isConfigured {
            Button(lang.t("检查更新…", "Check for Updates…")) { updater.checkForUpdates() }
                .disabled(!updater.canCheck)
        }
    }
}
