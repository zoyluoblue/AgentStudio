import Foundation

/// Plan B — drives the **Claude Agent SDK** (via the Node sidecar `tools/agent-bridge/bridge.mjs`)
/// for the Anthropic-key write lane. One sidecar process per turn: Swift writes a JSON command to
/// stdin and streams newline-delimited JSON events back from stdout. This gives the full Claude Code
/// agent harness (real Read/Write/Edit/Bash/Glob/Grep, sessions, MCP) instead of the hand-rolled loop.
///
/// Only used for `backend == .claude` in key mode. OpenAI/DeepSeek key lanes keep using `AgentEngine`
/// (native, provider-neutral); the local claude/codex CLIs (app mode) already self-agent.
enum AgentSDKClient {
    struct Result: Sendable {
        var ok: Bool; var text: String
        var input: Int; var output: Int; var costUSD: Double
        var error: String?; var changed: [String]; var sessionId: String?
    }

    /// node + bridge script, or nil if either is unavailable (caller then falls back to AgentEngine).
    /// The bridge is bundled into the app's Resources for release; the path is overridable for tests.
    static func locate() -> (node: String, script: String)? {
        guard let node = PathResolver.resolve("node") else { return nil }
        if let res = Bundle.main.url(forResource: "bridge", withExtension: "mjs", subdirectory: "agent-bridge"),
           FileManager.default.fileExists(atPath: res.path) {
            return (node, res.path)
        }
        return nil
    }

    /// Whether the sidecar's dependencies are installed next to the script (node_modules present).
    static func isInstalled(script: String) -> Bool {
        let dir = (script as NSString).deletingLastPathComponent
        return FileManager.default.fileExists(atPath: dir + "/node_modules/@anthropic-ai/claude-agent-sdk")
    }

    static func run(node: String, script: String, lane: Lane, model: String, system: String, prompt: String,
                    cwd: String, settings: AppSettings, resume: String? = nil,
                    onText: @escaping @Sendable (String) -> Void,
                    onActivity: @escaping @Sendable (String) -> Void) async -> Result {
        let key = settings.apiKey(for: lane)
        guard !key.isEmpty else {
            return Result(ok: false, text: "", input: 0, output: 0, costUSD: 0,
                          error: ProviderError.missingKey(.claude).errorDescription, changed: [], sessionId: nil)
        }
        var cmd: [String: Any] = [
            "prompt": prompt, "cwd": cwd, "model": model, "system": system,
            "apiKey": key, "baseURL": settings.effectiveBaseURL(for: lane),
            "allowCommands": settings.allowCommands,
        ]
        if let resume { cmd["resume"] = resume }
        let mcp = MCPConfig.enabled(settings)
        if !mcp.isEmpty { cmd["mcpServers"] = sdkMcpServers(mcp) }
        guard let data = try? JSONSerialization.data(withJSONObject: cmd),
              var line = String(data: data, encoding: .utf8) else {
            return Result(ok: false, text: "", input: 0, output: 0, costUSD: 0, error: "failed to encode command", changed: [], sessionId: nil)
        }
        line += "\n"

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: node)
        proc.arguments = [script]
        proc.currentDirectoryURL = URL(fileURLWithPath: cwd)
        proc.environment = PathResolver.loginEnv   // node needs PATH/HOME; the bridge re-curates env for claude
        let stdinPipe = Pipe(), stdoutPipe = Pipe(), stderrPipe = Pipe()
        proc.standardInput = stdinPipe; proc.standardOutput = stdoutPipe; proc.standardError = stderrPipe

        do { try proc.run() } catch {
            return Result(ok: false, text: "", input: 0, output: 0, costUSD: 0,
                          error: "无法启动 Node 桥接：\(error.localizedDescription)", changed: [], sessionId: nil)
        }
        stdinPipe.fileHandleForWriting.write(Data(line.utf8))
        try? stdinPipe.fileHandleForWriting.close()

        // Drain stderr concurrently — otherwise a chatty `claude` could fill the pipe buffer (~64KB)
        // and block, which would deadlock the stdout read below (it waits for stdout that never comes).
        let stderrHandle = stderrPipe.fileHandleForReading
        let stderrTask = Task<String, Never> { @Sendable in
            (try? stderrHandle.readToEnd()).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        }

        var result = Result(ok: false, text: "", input: 0, output: 0, costUSD: 0, error: nil, changed: [], sessionId: nil)
        var lastText = ""
        do {
            for try await raw in stdoutPipe.fileHandleForReading.bytes.lines {
                if Task.isCancelled { proc.terminate(); break }
                guard let d = raw.data(using: .utf8),
                      let ev = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                      let type = ev["type"] as? String else { continue }
                switch type {
                case "text":
                    if let t = ev["text"] as? String { lastText = t; onText(t) }
                case "tool":
                    if let n = ev["name"] as? String { onActivity(activity(n, ev)) }
                case "init":
                    result.sessionId = ev["sessionId"] as? String
                case "result":
                    result.ok = (ev["ok"] as? Bool) ?? false
                    let t = (ev["text"] as? String) ?? ""
                    result.text = t.isEmpty ? lastText : t
                    result.error = ev["error"] as? String
                    result.input = (ev["inputTokens"] as? Int) ?? 0
                    result.output = (ev["outputTokens"] as? Int) ?? 0
                    result.costUSD = (ev["costUSD"] as? Double) ?? 0
                    result.changed = (ev["changed"] as? [String]) ?? []
                    if let sid = ev["sessionId"] as? String { result.sessionId = sid }
                default: break
                }
            }
        } catch {
            if result.error == nil { result.error = "\(error)" }
        }
        proc.waitUntilExit()
        let errText = await stderrTask.value
        if !result.ok && (result.error?.isEmpty ?? true) {
            result.error = errText.isEmpty ? "Agent SDK 桥接未返回结果" : String(errText.suffix(400))
        }
        result.changed = dedupe(result.changed.map { relToCwd($0, cwd: cwd) })
        return result
    }

    // MCP servers in the SDK's stdio config shape.
    private static func sdkMcpServers(_ servers: [MCPServer]) -> [String: Any] {
        var out: [String: Any] = [:]
        for s in servers { out[s.id] = ["type": "stdio", "command": s.command, "args": s.args] }
        return out
    }

    private static func activity(_ name: String, _ ev: [String: Any]) -> String {
        let file = (ev["path"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
        switch name {
        case "Read": return "读取 \(file)…"
        case "Write": return "写入 \(file)…"
        case "Edit", "MultiEdit", "NotebookEdit": return "修改 \(file)…"
        case "Bash": return "运行命令…"
        case "Glob", "Grep": return "搜索中…"
        case "TodoWrite": return "整理任务…"
        default: return name.hasPrefix("mcp__") ? "调用工具…" : "\(name)…"
        }
    }

    private static func relToCwd(_ abs: String, cwd: String) -> String {
        let root = URL(fileURLWithPath: cwd).standardizedFileURL.path
        if abs == root { return "" }
        if abs.hasPrefix(root + "/") { return String(abs.dropFirst(root.count + 1)) }
        return URL(fileURLWithPath: abs).lastPathComponent
    }

    private static func dedupe(_ xs: [String]) -> [String] {
        var seen = Set<String>(); return xs.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
