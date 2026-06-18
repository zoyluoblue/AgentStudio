import AppKit
import Foundation

/// CLI-login auth (app / no-API-key mode): check status and run the interactive login,
/// reusing the user's terminal `claude` / `codex` login. Ported from auth.ts.
enum AgentAuth {
    /// Check whether the CLI is logged in. Times out so a stuck CLI can't hang the UI.
    /// `backend` chooses the binary (claude / codex); `lane` scopes the proxy env.
    static func status(backend: Backend, lane: Lane, cwd: String, settings: AppSettings = .defaults) async -> AuthStatus {
        await withTimeout(8, default: AuthStatus.disconnected) {
            backend == .claude ? await claudeStatus(cwd, lane, settings) : await codexStatus(cwd, lane, settings)
        }
    }

    private static func claudeStatus(_ cwd: String, _ lane: Lane, _ settings: AppSettings) async -> AuthStatus {
        guard let bin = PathResolver.resolve("claude") else { return AuthStatus(connected: false, detail: "未安装") }
        let r = await runProcessToEnd(bin, ["auth", "status"], cwd: cwd, env: cliEnv(lane: lane, backend: .claude, settings: settings))
        let raw = (r.stdout.isEmpty ? r.stderr : r.stdout).trimmed
        if let range = raw.range(of: "\\{[\\s\\S]*\\}", options: .regularExpression),
           let data = String(raw[range]).data(using: .utf8),
           let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           (j["loggedIn"] as? Bool) == true {
            return AuthStatus(connected: true, detail: (j["email"] as? String) ?? (j["authMethod"] as? String))
        }
        return .disconnected
    }

    private static func codexStatus(_ cwd: String, _ lane: Lane, _ settings: AppSettings) async -> AuthStatus {
        guard let bin = PathResolver.resolve("codex") else { return AuthStatus(connected: false, detail: "未安装") }
        let r = await runProcessToEnd(bin, ["login", "status"], cwd: cwd, env: cliEnv(lane: lane, backend: .codex, settings: settings))
        let raw = "\(r.stdout)\n\(r.stderr)".trimmed
        if raw.range(of: "not logged in|no (?:stored )?credentials|please .*log ?in", options: [.regularExpression, .caseInsensitive]) != nil {
            return .disconnected
        }
        if let m = raw.range(of: "logged in(?: using (.+))?", options: [.regularExpression, .caseInsensitive]) {
            return AuthStatus(connected: true, detail: String(raw[m]))
        }
        return .disconnected
    }

    /// Run the interactive login (opens a browser OAuth flow). Resolves once login lands,
    /// the process exits, or a 180s timeout. `onUrl` surfaces any printed URL as a fallback.
    static func login(backend: Backend, lane: Lane, cwd: String, settings: AppSettings = .defaults, onUrl: @escaping (String) -> Void) async -> AuthStatus {
        let cmd = backend == .claude ? "claude" : "codex"
        guard let bin = PathResolver.resolve(cmd) else { return AuthStatus(connected: false, detail: "未安装") }
        let args = backend == .claude ? ["auth", "login"] : ["login"]
        let env = cliEnv(lane: lane, backend: backend, settings: settings)

        await withTimeout(180, default: ()) {
            var opened = false
            do {
                for try await ev in runProcess(bin, args, cwd: cwd, env: env) {
                    if case .line(let l) = ev, !opened,
                       let r = l.range(of: "https?://[^\\s'\"]+", options: .regularExpression) {
                        opened = true
                        let url = String(l[r])
                        onUrl(url)
                        if let u = URL(string: url) { await MainActor.run { NSWorkspace.shared.open(u) } }
                    }
                }
            } catch { /* process ended */ }
        }
        return await status(backend: backend, lane: lane, cwd: cwd, settings: settings)
    }
}

/// Run an async operation with a timeout; returns `default` if it doesn't finish in time.
func withTimeout<T: Sendable>(_ seconds: Double, default def: T, _ op: @escaping @Sendable () async -> T) async -> T {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { await op() }
        group.addTask { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)); return nil }
        for await first in group {
            group.cancelAll()
            if let first { return first }
            return def
        }
        return def
    }
}
