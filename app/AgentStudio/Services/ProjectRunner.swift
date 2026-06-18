import Foundation

/// R2 — one-click run. Detects how a non-coder's project should start (a Node dev script, a
/// Python entry, or a plain static page) and produces a `RunPlan`. The actual spawning reuses
/// `runProcess` / `PathResolver` (same login-shell PATH handling as the CLI lanes).
enum ProjectRunner {
    /// How to start the project.
    struct Plan: Sendable, Equatable {
        enum Kind: String, Sendable { case node, python, staticSite }
        var kind: Kind
        var label: String            // human command, e.g. "npm run dev"
        var bin: String?             // resolved executable (nil for staticSite)
        var args: [String]
        var packageManager: String?  // npm / pnpm / yarn (node only)
        var needsInstall: Bool       // node_modules missing
        var entryFile: String?       // staticSite: index.html relpath; python: entry file
    }

    /// Inspect the project and decide the best way to run it. Pure filesystem work — call off-main.
    static func detect(cwd: String) -> Plan? {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: cwd)

        // 1. Node project with a runnable script.
        let pkg = root.appendingPathComponent("package.json")
        if let data = try? Data(contentsOf: pkg),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let scripts = (obj["scripts"] as? [String: Any]) ?? [:]
            let preferred = ["dev", "start", "serve", "preview"]
            if let script = preferred.first(where: { scripts[$0] != nil }) ?? scripts.keys.sorted().first {
                let pm = packageManager(root: root)
                let bin = PathResolver.resolve(pm) ?? PathResolver.resolve("npm")
                let args = pm == "yarn" ? [script] : ["run", script]
                let needsInstall = !fm.fileExists(atPath: root.appendingPathComponent("node_modules").path)
                return Plan(kind: .node, label: "\(pm) \(args.joined(separator: " "))", bin: bin,
                            args: args, packageManager: pm, needsInstall: needsInstall, entryFile: nil)
            }
        }

        // 2. Static page — no build, just open it.
        for cand in ["index.html", "public/index.html", "dist/index.html", "build/index.html", "src/index.html"] {
            if fm.fileExists(atPath: root.appendingPathComponent(cand).path) {
                return Plan(kind: .staticSite, label: cand, bin: nil, args: [],
                            packageManager: nil, needsInstall: false, entryFile: cand)
            }
        }

        // 3. Python entry.
        for cand in ["app.py", "main.py", "manage.py", "server.py"] {
            if fm.fileExists(atPath: root.appendingPathComponent(cand).path) {
                let bin = PathResolver.resolve("python3") ?? PathResolver.resolve("python")
                let args = cand == "manage.py" ? [cand, "runserver"] : [cand]
                return Plan(kind: .python, label: "python \(args.joined(separator: " "))", bin: bin,
                            args: args, packageManager: nil, needsInstall: false, entryFile: cand)
            }
        }

        return nil
    }

    private static func packageManager(root: URL) -> String {
        let fm = FileManager.default
        if fm.fileExists(atPath: root.appendingPathComponent("pnpm-lock.yaml").path) { return "pnpm" }
        if fm.fileExists(atPath: root.appendingPathComponent("yarn.lock").path) { return "yarn" }
        return "npm"
    }

    /// Pull the first local dev-server URL out of a log line (Vite/CRA/etc. print these).
    static func detectURL(in line: String) -> String? {
        let pattern = "https?://(?:localhost|127\\.0\\.0\\.1|0\\.0\\.0\\.0)(?::\\d+)?[^\\s\"'`]*"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = line as NSString
        guard let m = re.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        var url = ns.substring(with: m.range)
        url = url.replacingOccurrences(of: "0.0.0.0", with: "localhost")
        return url.trimmingCharacters(in: CharacterSet(charactersIn: ".,)]}>"))
    }

    /// Strip ANSI color/escape codes so logs read cleanly.
    static func stripANSI(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]", with: "", options: .regularExpression)
    }

    /// High-signal build/compile error markers in a dev-server log line (narrow, to avoid noise).
    /// Returns the cleaned line if it looks like a real error, else nil.
    static func buildError(in line: String) -> String? {
        let markers = ["Failed to compile", "Module not found", "Cannot find module", "SyntaxError",
                       "error TS", "ERR!", "Build failed", "Internal server error",
                       "Unexpected token", "is not defined", "Cannot resolve"]
        let lower = line.lowercased()
        // skip obvious "0 errors" / summary noise
        if lower.contains("0 error") || lower.contains("no error") { return nil }
        guard markers.contains(where: { line.contains($0) }) else { return nil }
        return line.trimmingCharacters(in: .whitespaces)
    }
}

/// Live state of the current run (one project at a time). Held on the @MainActor controller.
enum RunStatus: Sendable, Equatable { case idle, installing, starting, running, stopped, failed }

struct RunState: Equatable {
    var status: RunStatus = .idle
    var plan: ProjectRunner.Plan?
    var logs: [String] = []
    var url: String?
    var message: String = ""
    var reloadNonce = 0   // bump → the preview web view reloads (used by self-heal)

    var isActive: Bool { status == .installing || status == .starting || status == .running }
}

/// R3 — a runtime/visual problem detected while the project runs: a JS error, a failed page load,
/// a blank render, or a build error in the logs. Fed back to the executor for one-click self-heal.
struct RunIssue: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable, CaseIterable {
        case js, console, promise, resource, blank, navigation, build
        /// Short human label.
        func label(_ l: Lang) -> String {
            switch self {
            case .js, .console, .promise: return l.t("脚本报错", "Script error")
            case .resource: return l.t("资源加载失败", "Resource failed")
            case .blank: return l.t("页面空白", "Blank page")
            case .navigation: return l.t("页面打不开", "Page won't load")
            case .build: return l.t("编译报错", "Build error")
            }
        }
    }
    var id: String        // dedup key
    var kind: Kind
    var message: String
}
