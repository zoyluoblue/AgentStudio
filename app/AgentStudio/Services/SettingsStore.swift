import Foundation
import Observation

/// Loads, mutates and persists user preferences. The live object is observed by the UI;
/// background services receive a Sendable `AppSettings` value snapshot per call.
/// `settings` is directly bindable from SwiftUI.
///
/// ALL Keychain I/O is kept OFF the main thread — a synchronous Keychain call on the main
/// thread (which can block on securityd or an access-permission prompt) beach-balls the UI on
/// every keystroke / picker change. Writes are debounced + dispatched off-main; the API keys
/// are read in the background after launch. The in-memory `settings` is always current, so
/// reads by the engine are unaffected.
@MainActor
@Observable
final class SettingsStore {
    var settings: AppSettings {
        didSet { if !applyingKeychain { scheduleSave() } }
    }

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var applyingKeychain = false

    init() {
        // JSON prefs only — API keys are read from the Keychain lazily (on Connect), so the
        // app never triggers a Keychain access prompt just by launching.
        settings = Self.loadPrefs()
    }

    var snapshot: AppSettings { settings }

    func update(_ change: (inout AppSettings) -> Void) { change(&settings) }

    /// Put a key into the in-memory settings WITHOUT re-persisting it (used after a lazy
    /// Keychain read on Connect).
    func loadKeyInMemory(_ lane: Lane, _ v: String) {
        applyingKeychain = true
        settings.apiKeys[lane] = v
        applyingKeychain = false
    }

    /// Persist immediately (e.g. before quit) without waiting for the debounce.
    func flush() {
        saveTask?.cancel()
        Self.persist(settings)
    }

    // ---- load ----

    private static func loadPrefs() -> AppSettings {
        guard let data = try? Data(contentsOf: AppPaths.settingsFile) else { return .defaults }
        do {
            return try JSONDecoder().decode(AppSettings.self, from: data) // apiKeys excluded → empty
        } catch {
            Log.shared.event("settings.load.error", ["err": "\(error)"])
            return .defaults
        }
    }

    // ---- save (debounced, off-main) ----

    private func scheduleSave() {
        // IMPORTANT: do NOT read `settings` here — this runs inside `settings.didSet`, which is
        // still inside the exclusive write access of the mutation that triggered it. Reading
        // `settings` now is a simultaneous read+write → Swift exclusivity trap. Read it later,
        // inside the async task, after the mutation has fully completed.
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000) // coalesce bursts of edits
            guard !Task.isCancelled, let self else { return }
            Self.persist(self.settings)
        }
    }

    nonisolated private static func persist(_ s: AppSettings) {
        DispatchQueue.global(qos: .utility).async {
            KeychainStore.saveKeys(s.apiKeys)
            do {
                let enc = JSONEncoder()
                enc.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try enc.encode(s)
                try data.write(to: AppPaths.settingsFile, options: .atomic)
            } catch {
                Log.shared.event("settings.save.error", ["err": "\(error)"])
            }
        }
    }
}
