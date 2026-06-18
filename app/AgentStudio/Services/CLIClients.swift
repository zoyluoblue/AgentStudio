import Foundation

/// A dropped/closed/reset connection or a timeout in CLI output — worth retrying (flaky proxy/relay).
func cliErrorIsTransient(_ msg: String?) -> Bool {
    guard let m = msg?.lowercased() else { return false }
    return m.range(of: "socket|closed|reset|econnreset|etimedout|timed ?out|network|fetch failed|terminated|\\beof\\b|connection error|enotfound|getaddrinfo|stream error",
                   options: .regularExpression) != nil
}

/// Replace a CLI's cryptic network message with a clear, actionable one after retries are exhausted.
func cliFriendlyError(_ r: CLIResult, _ settings: AppSettings) -> CLIResult {
    var r = r
    r.error = settings.language.t(
        "网络连接被反复中断（已自动重试）。多半是本地代理 / 中转此刻不稳定——可在「设置」里把代理改为自定义 HTTP 代理后重试。",
        "The connection kept dropping (auto-retried). Usually a flaky local proxy/relay — try setting a custom HTTP proxy in Settings and retry.")
    return r
}

/// Result of a CLI-driven turn (app / login mode — no API key).
struct CLIResult: Sendable {
    var ok: Bool
    var text: String
    var error: String?
    /// resume handle for multi-turn continuity (claude session id / codex thread id)
    var resumeId: String?
    var steps: Int = 0
}

// MARK: - Claude Code CLI

enum ClaudeCLI {
    // Disabling every tool makes `claude -p` answer in one clean turn.
    private static let allTools = ["Bash", "Edit", "Write", "MultiEdit", "NotebookEdit", "Read", "Glob", "Grep", "Task", "Agent", "WebFetch", "WebSearch", "TodoWrite"]
    // Executor mode: let Claude read + edit files non-interactively.
    private static let writeTools = ["Edit", "Write", "MultiEdit", "Read", "Glob", "Grep", "LS", "TodoWrite"]

    /// Run `claude -p` reusing the user's CLI login (no API key). Single JSON envelope.
    /// Retries transient network drops (e.g. "socket connection was closed") with backoff, the way
    /// the HTTP path does — these are common with flaky proxies/relays and usually clear on retry.
    static func run(prompt: String, cwd: String, system: String?, model: String?, write: Bool, resumeId: String?, lane: Lane, settings: AppSettings) async -> CLIResult {
        guard let bin = PathResolver.resolve("claude") else {
            return CLIResult(ok: false, text: "", error: "claude 未找到（PATH）。请确认已安装 Claude Code CLI。")
        }
        var argv = ["-p", prompt, "--output-format", "json"]
        if let system, !system.isEmpty { argv += ["--append-system-prompt", system] }
        if let model, !model.isEmpty { argv += ["--model", model] }
        if let resumeId, !resumeId.isEmpty { argv += ["--resume", resumeId] }
        argv += ["--add-dir", cwd]
        // v2.0 — register the user's MCP servers so the agent can call them as tools.
        let mcp = MCPConfig.enabled(settings)
        if let cfg = MCPConfig.claudeConfigFile(mcp) { argv += ["--mcp-config", cfg] }
        if write {
            // A-line: let the executor run commands (install deps, tests, git, dev servers) when allowed.
            let tools = writeTools + (settings.allowCommands ? ["Bash"] : []) + MCPConfig.claudeAllowTools(mcp)
            argv += ["--permission-mode", "acceptEdits", "--allowedTools"] + tools
        } else { argv += ["--disallowedTools"] + allTools }

        let env = cliEnv(lane: lane, backend: .claude, settings: settings)
        var attempt = 0
        while true {
            if Task.isCancelled { return CLIResult(ok: false, text: "", error: settings.language.t("已停止", "Stopped")) }
            let r = await runProcessToEnd(bin, argv, cwd: cwd, env: env)
            let result = parseEnvelope(r.stdout, code: r.code, stderr: r.stderr)
            if result.ok || attempt >= 2 || !cliErrorIsTransient(result.error) {
                return attempt >= 2 && cliErrorIsTransient(result.error) ? cliFriendlyError(result, settings) : result
            }
            attempt += 1
            let backoff = min(0.8 * pow(2, Double(attempt - 1)), 5.0)
            try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
        }
    }

    private static func parseEnvelope(_ out: String, code: Int32, stderr: String) -> CLIResult {
        let trimmed = out.trimmed
        guard !trimmed.isEmpty else {
            return CLIResult(ok: false, text: "", error: stderr.trimmed.isEmpty ? "claude 退出码 \(code)" : stderr.trimmed)
        }
        guard let data = trimmed.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return code == 0 ? CLIResult(ok: true, text: trimmed) : CLIResult(ok: false, text: trimmed, error: "claude 退出码 \(code)")
        }
        let text = o["result"] as? String ?? ""
        let sid = o["session_id"] as? String
        if (o["is_error"] as? Bool) == true {
            return CLIResult(ok: false, text: text, error: (o["error"] as? String) ?? (text.isEmpty ? "claude 出错" : text), resumeId: sid)
        }
        if code != 0 { return CLIResult(ok: false, text: text, error: "claude 退出码 \(code)", resumeId: sid) }
        return CLIResult(ok: true, text: text, error: nil, resumeId: sid)
    }
}

// MARK: - Codex CLI

enum CodexCLI {
    enum Sandbox: String { case readOnly = "read-only", workspaceWrite = "workspace-write" }

    /// Streamed codex events; the main-actor caller consumes these so UI updates stay on main.
    enum Event: Sendable {
        case delta(String)
        case status(String)
        case done(CLIResult)
    }

    /// Run `codex exec` (or resume) reusing the ChatGPT login, streaming agent messages.
    static func run(prompt: String, cwd: String, sandbox: Sandbox, model: String?, threadId: String?, lane: Lane, settings: AppSettings) -> AsyncThrowingStream<Event, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                guard let bin = PathResolver.resolve("codex") else {
                    continuation.yield(.done(CLIResult(ok: false, text: "", error: "codex 未找到（PATH）。请确认已安装 Codex CLI。")))
                    continuation.finish(); return
                }
                var args = ["exec"]
                if let threadId, !threadId.isEmpty { args += ["resume", threadId] }
                args += ["--json", "--skip-git-repo-check"]
                args += ["-c", "features.memories=false", "-c", "features.goals=false", "-c", "features.chronicle=false"]
                args += MCPConfig.codexConfigArgs(MCPConfig.enabled(settings)) // v2.0 — MCP servers
                if let threadId, !threadId.isEmpty { args += ["-c", "sandbox_mode=\(sandbox.rawValue)"] } else { args += ["-s", sandbox.rawValue] }
                if let model, !model.isEmpty { args += ["-m", model] }
                args.append(prompt)
                let env = cliEnv(lane: lane, backend: .codex, settings: settings)

                var thread = threadId
                var attempt = 0
                while true {
                    var text = "", steps = 0
                    var failure: String?
                    do {
                        for try await ev in runProcess(bin, args, cwd: cwd, env: env) {
                            switch ev {
                            case .line(let line):
                                let s = line.trimmed
                                guard !s.isEmpty, let d = s.data(using: .utf8),
                                      let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { continue }
                                let type = obj["type"] as? String
                                if type == "thread.started", let id = obj["thread_id"] as? String {
                                    thread = id
                                } else if type == "item.started" {
                                    if let st = itemStatus(obj["item"] as? [String: Any]) { continuation.yield(.status(st)) }
                                } else if type == "item.completed", let item = obj["item"] as? [String: Any] {
                                    if item["type"] as? String == "agent_message", let t = item["text"] as? String {
                                        text += (text.isEmpty ? "" : "\n") + t
                                        continuation.yield(.delta(text))
                                    } else if item["type"] != nil {
                                        steps += 1
                                        if let st = itemStatus(item) { continuation.yield(.status(st)) }
                                    }
                                } else if type == "error", let msg = obj["message"] as? String {
                                    failure = msg
                                }
                            case .finished(let code, let stderr):
                                if failure == nil && text.isEmpty && code != 0 {
                                    failure = stderr.trimmed.isEmpty ? "codex 退出码 \(code)" : stderr.trimmed
                                }
                            }
                        }
                    } catch {
                        failure = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                    }

                    // Retry a transient drop that produced no output (mirrors the HTTP/Claude paths).
                    if text.isEmpty, cliErrorIsTransient(failure), attempt < 2, !Task.isCancelled {
                        attempt += 1
                        continuation.yield(.status(settings.language.t("重连中…", "Reconnecting…")))
                        let backoff = min(0.8 * pow(2, Double(attempt - 1)), 5.0)
                        try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                        continue
                    }

                    let result: CLIResult
                    if let failure, text.isEmpty {
                        let base = CLIResult(ok: false, text: "", error: failure, resumeId: thread, steps: steps)
                        result = cliErrorIsTransient(failure) ? cliFriendlyError(base, settings) : base
                    } else {
                        let suffix = steps > 0 ? "\n\n（执行了 \(steps) 步操作）" : ""
                        result = CLIResult(ok: true, text: (text.isEmpty ? "（已完成）" : text) + suffix, resumeId: thread, steps: steps)
                    }
                    continuation.yield(.done(result))
                    continuation.finish()
                    break
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func itemStatus(_ item: [String: Any]?) -> String? {
        switch item?["type"] as? String {
        case "reasoning": return "思考中"
        case "command_execution":
            let cmd = (item?["command"] as? String ?? "").replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmed
            return cmd.isEmpty ? "运行命令中" : "运行命令：\(String(cmd.prefix(36)))"
        case "file_change": return "修改文件中"
        case "mcp_tool_call": return "调用工具中"
        case "web_search": return "联网搜索中"
        case "agent_message": return "整理结果中"
        case .some: return "执行中"
        default: return nil
        }
    }

    /// Models the `codex -m` flag accepts, read from `~/.codex/models_cache.json`.
    static func cachedModels() -> [ModelOption] {
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/models_cache.json")
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = obj["models"] as? [[String: Any]] else { return [] }
        return models.compactMap { m in
            guard m["visibility"] as? String == "list", let slug = m["slug"] as? String else { return nil }
            return ModelOption(id: slug, label: (m["display_name"] as? String) ?? slug)
        }
    }
}
