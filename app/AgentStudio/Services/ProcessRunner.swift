import Foundation

/// Resolves CLI binaries when launched as a GUI app (which doesn't inherit the shell PATH),
/// mirroring which.ts + fixPath.ts. Computes an augmented PATH once from the login shell.
enum PathResolver {
    private static let fallbackDirs = [
        "/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin",
        "\(NSHomeDirectory())/.local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin",
    ]

    /// PATH augmented with the login shell's PATH + common install dirs.
    /// Computed once, lazily, off the main thread (heavy `.zshrc` can't block the UI).
    static let path: String = {
        var dirs: [String] = []
        // login shell PATH (Homebrew/npm installs live here)
        dirs.append(contentsOf: (loginEnv["PATH"] ?? "").split(separator: ":").map(String.init))
        dirs.append(contentsOf: (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init))
        dirs.append(contentsOf: fallbackDirs)
        var seen = Set<String>(); var ordered: [String] = []
        for d in dirs where !d.isEmpty && seen.insert(d).inserted { ordered.append(d) }
        return ordered.joined(separator: ":")
    }()

    /// The login shell's full environment, captured once. A GUI app launched from Finder/Xcode
    /// does NOT inherit the user's shell config, so CLIs we spawn (claude / codex) would miss the
    /// user's `ANTHROPIC_BASE_URL` / `ANTHROPIC_AUTH_TOKEN` relay setup, proxies, etc. — exactly
    /// what makes `claude` work in their terminal. Reusing it is the whole point of "app mode".
    static let loginEnv: [String: String] = {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        // `-i` so interactive-only rc files (where exports often live) are sourced too.
        return parseEnv(loginShellOutput(shell, command: "env"))
    }()

    /// Run `<shell> -ilc <command>` and capture stdout, bounded to 4s so a heavy profile can't hang us.
    private static func loginShellOutput(_ shell: String, command: String) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: shell)
        p.arguments = ["-ilc", command]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return "" }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 4, execute: killer)
        let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
        p.waitUntilExit()
        killer.cancel()
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Parse `KEY=VALUE` lines (as printed by `env`) into a dictionary.
    private static func parseEnv(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[line.startIndex..<eq])
            let val = String(line[line.index(after: eq)...])
            if !key.isEmpty { out[key] = val }
        }
        return out
    }

    /// Resolve a bare command to an absolute executable path, or nil.
    static func resolve(_ cmd: String) -> String? {
        if cmd.contains("/") { return FileManager.default.isExecutableFile(atPath: cmd) ? cmd : nil }
        for d in path.split(separator: ":") {
            let full = "\(d)/\(cmd)"
            if FileManager.default.isExecutableFile(atPath: full) { return full }
        }
        return nil
    }
}

enum ProcEvent: Sendable {
    case line(String)
    case finished(code: Int32, stderr: String)
}

/// Spawn a process and stream its stdout line-by-line, then a final `.finished` event
/// carrying exit code + full stderr. Cancelling the consuming task terminates the process.
func runProcess(_ bin: String, _ args: [String], cwd: String?, env: [String: String]) -> AsyncThrowingStream<ProcEvent, Error> {
    AsyncThrowingStream { continuation in
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: bin)
        proc.arguments = args
        proc.environment = env
        if let cwd { proc.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        let outPipe = Pipe(), errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        proc.standardInput = FileHandle.nullDevice

        let lock = NSLock()
        var buffer = Data()

        outPipe.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            guard !d.isEmpty else { return }
            lock.lock(); defer { lock.unlock() }
            buffer.append(d)
            while let nl = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer.subdata(in: buffer.startIndex..<nl)
                buffer.removeSubrange(buffer.startIndex...nl)
                if let s = String(data: lineData, encoding: .utf8) { continuation.yield(.line(s)) }
            }
        }

        proc.terminationHandler = { p in
            outPipe.fileHandleForReading.readabilityHandler = nil
            lock.lock()
            let rest = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
            if !rest.isEmpty { buffer.append(rest) }
            if !buffer.isEmpty, let s = String(data: buffer, encoding: .utf8), !s.isEmpty {
                for line in s.split(separator: "\n", omittingEmptySubsequences: true) { continuation.yield(.line(String(line))) }
            }
            buffer.removeAll()
            lock.unlock()
            let errData = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
            continuation.yield(.finished(code: p.terminationStatus, stderr: String(data: errData, encoding: .utf8) ?? ""))
            continuation.finish()
        }

        continuation.onTermination = { _ in
            if proc.isRunning { proc.terminate() }
        }

        do { try proc.run() } catch {
            continuation.finish(throwing: ProviderError.other("无法启动 \(bin)：\(error.localizedDescription)"))
        }
    }
}

/// Run a process to completion, capturing all stdout/stderr (used for auth status checks).
func runProcessToEnd(_ bin: String, _ args: [String], cwd: String?, env: [String: String]) async -> (code: Int32, stdout: String, stderr: String) {
    var out = "", err = "", code: Int32 = -1
    do {
        for try await ev in runProcess(bin, args, cwd: cwd, env: env) {
            switch ev {
            case .line(let l): out += l + "\n"
            case .finished(let c, let e): code = c; err = e
            }
        }
    } catch { err = "\(error)" }
    return (code, out, err)
}

/// Build a child-process env for an app-mode CLI run. Starts from the user's *login-shell*
/// environment (so `claude` / `codex` see the same relay / auth-token / proxy config that makes
/// them work in the terminal — a GUI app doesn't inherit this), augments PATH, then applies the
/// app's proxy override. We intentionally do NOT strip `ANTHROPIC_*` / `CLAUDE_CODE_*`: in app
/// mode those are the user's own login config, not anything we injected.
func cliEnv(lane: Lane, backend: Backend, settings: AppSettings) -> [String: String] {
    var e = ProcessInfo.processInfo.environment
    for (k, v) in PathResolver.loginEnv { e[k] = v } // shell config wins over the sparse GUI env
    e["PATH"] = PathResolver.path
    let proxyKeys = ["HTTP_PROXY", "HTTPS_PROXY", "http_proxy", "https_proxy", "ALL_PROXY", "all_proxy"]
    let inScope = settings.proxyScope == .both || settings.proxyScope.rawValue == lane.rawValue
    if settings.proxyMode == .none || !inScope {
        for k in proxyKeys { e[k] = nil }
    } else if settings.proxyMode == .custom, !settings.proxyUrl.trimmed.isEmpty {
        // Clear everything first so a stray inherited ALL_PROXY (often SOCKS, which the CLI's
        // fetch can't use → "socket closed") can't shadow the explicit HTTP proxy.
        for k in proxyKeys { e[k] = nil }
        let u = settings.proxyUrl.trimmed
        e["HTTP_PROXY"] = u; e["HTTPS_PROXY"] = u; e["http_proxy"] = u; e["https_proxy"] = u
    }
    // proxyMode == .system → leave whatever the login shell exported (the user's own proxy).
    return e
}
