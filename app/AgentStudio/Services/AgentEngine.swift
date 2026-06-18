import Foundation

/// A2 — a real tool-use agent loop for the HTTP/key path. Instead of one-shot file output, the
/// model can list/read/write/edit files and (when allowed) run commands, iterating until done.
/// Non-streaming per step (simpler + robust); progress is surfaced via `onActivity`.
/// Supports the Anthropic (tool_use) and OpenAI (tool_calls) formats.
enum AgentEngine {
    struct Result: Sendable { var ok: Bool; var text: String; var input: Int; var output: Int; var error: String?; var changed: [String] }

    private struct ToolCall { let id: String; let name: String; let input: [String: Any] }

    static let maxSteps = 14

    /// Loop tracing — prints each step's stop reason, tool calls, and results to stderr. Defaults to
    /// the AS_DEBUG_TOOLS env flag; tests set it directly (Xcode doesn't forward shell env to the runner).
    static var debug = ProcessInfo.processInfo.environment["AS_DEBUG_TOOLS"] != nil
    private static func dbg(_ s: @autoclosure () -> String) {
        guard debug else { return }
        FileHandle.standardError.write(("[agent] " + s() + "\n").data(using: .utf8)!)
    }

    /// Run the agent loop. `changed` accumulates files the tools created/edited (for checkpoints).
    static func run(lane: Lane, backend: Backend, model: String, system: String, prompt: String,
                    cwd: String, settings: AppSettings, onActivity: @escaping @Sendable (String) -> Void) async -> Result {
        let key = settings.apiKey(for: lane)
        guard !key.isEmpty else { return Result(ok: false, text: "", input: 0, output: 0, error: ProviderError.missingKey(backend).errorDescription, changed: []) }
        let base = settings.effectiveBaseURL(for: lane)
        let session = ProxyConfig.session(settings: settings, lane: lane, direct: backend == .deepseek)
        let runner = ToolRunner(cwd: cwd, settings: settings, lane: lane)
        // Anchor the model on the real project root so it stops inventing absolute roots like /app.
        let rooted = "Project root (your working directory) is: \(cwd)\n" +
                     "Use file paths relative to it (e.g. `note.txt`, `src/app.js`), or this exact absolute path. " +
                     "Do NOT invent absolute roots like /app or /workspace.\n\n" + prompt
        do {
            if backend == .claude {
                return try await loopAnthropic(key: key, base: base, model: model, system: system, prompt: rooted,
                                                session: session, runner: runner, onActivity: onActivity)
            } else {
                return try await loopOpenAI(key: key, base: base, model: model, system: system, prompt: rooted,
                                            session: session, runner: runner, onActivity: onActivity)
            }
        } catch {
            return Result(ok: false, text: "", input: runner.usageIn, output: runner.usageOut,
                          error: (error as? LocalizedError)?.errorDescription ?? "\(error)", changed: runner.changed)
        }
    }

    // MARK: - Anthropic loop

    private static func loopAnthropic(key: String, base: String, model: String, system: String, prompt: String,
                                      session: URLSession, runner: ToolRunner, onActivity: @Sendable (String) -> Void) async throws -> Result {
        var messages: [[String: Any]] = [["role": "user", "content": prompt]]
        let tools = ToolRunner.anthropicTools(runner.settings)
        var inTok = 0, outTok = 0, finalText = ""
        for step in 0..<maxSteps {
            try Task.checkCancellation()
            let body: [String: Any] = ["model": model, "max_tokens": 8000, "system": system, "tools": tools, "messages": messages]
            guard let url = URL(string: "\(base)/v1/messages") else { throw ProviderError.other("无效 Base URL") }
            var req = URLRequest(url: url); req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(key, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, resp) = try await session.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                throw classifyHTTP((resp as? HTTPURLResponse)?.statusCode ?? 0, body: String(data: data, encoding: .utf8) ?? "")
            }
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ProviderError.empty }
            if let u = obj["usage"] as? [String: Any] { inTok += (u["input_tokens"] as? Int) ?? 0; outTok += (u["output_tokens"] as? Int) ?? 0 }
            let content = (obj["content"] as? [[String: Any]]) ?? []
            dbg("step \(step) stop=\(obj["stop_reason"] as? String ?? "?") blocks=\(content.map { $0["type"] as? String ?? "?" })")
            messages.append(["role": "assistant", "content": content])
            var calls: [ToolCall] = []
            for block in content {
                if block["type"] as? String == "text", let t = block["text"] as? String { finalText += t }
                else if block["type"] as? String == "tool_use", let id = block["id"] as? String, let name = block["name"] as? String {
                    calls.append(ToolCall(id: id, name: name, input: (block["input"] as? [String: Any]) ?? [:]))
                }
            }
            if calls.isEmpty { break }              // model produced a final answer
            var results: [[String: Any]] = []
            for c in calls {
                onActivity(runner.activity(c.name, c.input))
                let out = await runner.execute(c.name, c.input)
                dbg("  call \(c.name)(\(c.input)) -> \(out.prefix(120))")
                results.append(["type": "tool_result", "tool_use_id": c.id, "content": out])
            }
            messages.append(["role": "user", "content": results])
        }
        return Result(ok: true, text: finalText, input: inTok, output: outTok, error: nil, changed: runner.changed)
    }

    // MARK: - OpenAI loop

    private static func loopOpenAI(key: String, base: String, model: String, system: String, prompt: String,
                                   session: URLSession, runner: ToolRunner, onActivity: @Sendable (String) -> Void) async throws -> Result {
        var messages: [[String: Any]] = [["role": "system", "content": system], ["role": "user", "content": prompt]]
        let tools = ToolRunner.openAITools(runner.settings)
        var inTok = 0, outTok = 0, finalText = ""
        for _ in 0..<maxSteps {
            try Task.checkCancellation()
            let body: [String: Any] = ["model": model, "messages": messages, "tools": tools]
            guard let url = URL(string: "\(base)/chat/completions") else { throw ProviderError.other("无效 Base URL") }
            var req = URLRequest(url: url); req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, resp) = try await session.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                throw classifyHTTP((resp as? HTTPURLResponse)?.statusCode ?? 0, body: String(data: data, encoding: .utf8) ?? "")
            }
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ProviderError.empty }
            if let u = obj["usage"] as? [String: Any] { inTok += (u["prompt_tokens"] as? Int) ?? 0; outTok += (u["completion_tokens"] as? Int) ?? 0 }
            guard let msg = (obj["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any] else { throw ProviderError.empty }
            messages.append(msg)               // echo the assistant message (incl. tool_calls) verbatim
            if let t = msg["content"] as? String { finalText += t }
            guard let toolCalls = msg["tool_calls"] as? [[String: Any]], !toolCalls.isEmpty else { break }
            for tc in toolCalls {
                guard let id = tc["id"] as? String, let fn = tc["function"] as? [String: Any], let name = fn["name"] as? String else { continue }
                let args = (fn["arguments"] as? String).flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] } ?? [:]
                onActivity(runner.activity(name, args))
                let out = await runner.execute(name, args)
                messages.append(["role": "tool", "tool_call_id": id, "content": out])
            }
        }
        return Result(ok: true, text: finalText, input: inTok, output: outTok, error: nil, changed: runner.changed)
    }
}

/// Executes the agent's tools against the project, tracking which files changed.
final class ToolRunner: @unchecked Sendable {
    let cwd: String
    let settings: AppSettings
    let lane: Lane
    private(set) var changed: [String] = []
    private(set) var usageIn = 0, usageOut = 0

    init(cwd: String, settings: AppSettings, lane: Lane) { self.cwd = cwd; self.settings = settings; self.lane = lane }

    func activity(_ name: String, _ input: [String: Any]) -> String {
        let arg = str(input, "file_path", "path") ?? str(input, "command") ?? ""
        switch ToolRunner.canonical(name) {
        case "list_files": return "列出文件…"
        case "Read": return "读取 \(arg)…"
        case "Write": return "写入 \(arg)…"
        case "Edit": return "修改 \(arg)…"
        case "Bash": return "运行：\(String(arg.prefix(40)))…"
        default: return "\(name)…"
        }
    }

    func execute(_ rawName: String, _ input: [String: Any]) async -> String {
        switch ToolRunner.canonical(rawName) {
        case "list_files":
            let m = ProjectFiles.projectMap(cwd)
            return m.isEmpty ? "(empty project — no files yet)" : m
        case "Read":
            guard let p = str(input, "file_path", "path") else { return "error: Read needs file_path" }
            let abs = URL(fileURLWithPath: cwd).appendingPathComponent(rel(p)).standardizedFileURL
            guard inRoot(abs) else { return "error: \(p) is outside the project" }
            return (try? String(contentsOf: abs, encoding: .utf8)) ?? "error: cannot read \(p) — it may not exist yet (use list_files to see what's there)."
        case "Write":
            guard let p = str(input, "file_path", "path"), let c = str(input, "content") else { return "error: Write needs file_path and content" }
            let w = ProjectFiles.applyFiles(cwd: cwd, files: [.init(path: rel(p), content: c)])
            if w.isEmpty { return "error: write refused for \(p) (path escapes the project)" }
            changed.append(contentsOf: w); return "OK — wrote \(w[0])"
        case "Edit":
            guard let p = str(input, "file_path", "path"),
                  let oldS = str(input, "old_string", "search"),
                  let newS = str(input, "new_string", "replace") else { return "error: Edit needs file_path, old_string and new_string" }
            let res = ProjectFiles.applyEdits(cwd: cwd, edits: [.init(path: rel(p), search: oldS, replace: newS)])
            if res.applied.isEmpty {
                return "error: old_string was not found in \(p). Read the file again and copy an exact, verbatim snippet (matching whitespace); or use Write to replace the whole file."
            }
            changed.append(contentsOf: res.applied); return "OK — edited \(res.applied[0])"
        case "Bash":
            guard settings.allowCommands else { return "error: running commands is disabled. Edit files directly instead (the user can enable commands in Settings → Agent capabilities)." }
            guard let cmd = str(input, "command"), let sh = PathResolver.resolve("zsh") ?? PathResolver.resolve("bash") else { return "error: Bash needs a command" }
            let env = cliEnv(lane: lane, backend: settings.backend(for: lane), settings: settings)
            let r = await runProcessToEnd(sh, ["-lc", cmd], cwd: cwd, env: env)
            let tail = (r.stdout + (r.stderr.isEmpty ? "" : "\n[stderr] " + r.stderr)).trimmed
            return "exit \(r.code)\n" + String(tail.suffix(6000))
        default:
            let avail = "Read, Write, Edit, list_files" + (settings.allowCommands ? ", Bash" : "")
            return "error: no tool named \(rawName). Use one of: \(avail)."
        }
    }

    /// Pull the first present key from `input` as a String (so we accept either provider's param names).
    private func str(_ input: [String: Any], _ keys: String...) -> String? {
        for k in keys { if let v = input[k] as? String { return v } }
        return nil
    }

    /// Map any reasonable alias the model emits onto our canonical tool name. Claude is trained on
    /// Read/Write/Edit/Bash (with file_path/old_string/new_string); other models use snake_case — both work.
    static func canonical(_ n: String) -> String {
        switch n.lowercased() {
        case "read", "read_file", "readfile", "cat", "view", "open_file": return "Read"
        case "write", "write_file", "writefile", "create_file", "createfile", "create", "save_file": return "Write"
        case "edit", "edit_file", "editfile", "str_replace", "str_replace_editor", "str_replace_based_edit_tool", "replace", "apply_patch", "patch": return "Edit"
        case "list_files", "listfiles", "ls", "glob", "list", "listdir", "list_dir", "tree", "find": return "list_files"
        case "bash", "run_command", "runcommand", "shell", "sh", "exec", "run", "command", "terminal": return "Bash"
        default: return n
        }
    }

    private func inRoot(_ abs: URL) -> Bool {
        let r = URL(fileURLWithPath: cwd).standardizedFileURL.path
        return abs.path == r || abs.path.hasPrefix(r + "/")
    }

    /// Normalize a model-supplied path to a clean path relative to the project root. Models (Claude
    /// especially) often assume a sandbox root like `/app` or `/workspace` and send absolute paths
    /// such as `/app/note.txt`, which would otherwise land in a bogus `app/` subfolder. We honor a
    /// real-root-absolute path, strip `./`, and drop invented container-root segments from absolutes.
    func rel(_ raw: String) -> String {
        let root = URL(fileURLWithPath: cwd).standardizedFileURL.path
        var p = raw.trimmed
        if p == root { return "" }
        if p.hasPrefix(root + "/") { return String(p.dropFirst(root.count + 1)) }
        p = p.replacingOccurrences(of: "^\\./", with: "", options: .regularExpression)
        let wasAbsolute = p.hasPrefix("/")
        p = p.replacingOccurrences(of: "^/+", with: "", options: .regularExpression)
        if wasAbsolute {
            // The leading segment of an invented absolute path is a sandbox-root guess, not a real
            // folder in the project — peel known container roots so the file lands at the real root.
            let containers: Set<String> = ["app", "apps", "workspace", "workspaces", "work", "project",
                "projects", "proj", "repo", "repos", "code", "srv", "home", "root", "usr", "mnt",
                "media", "data", "var", "private", "tmp", "users"]
            var segs = p.split(separator: "/").map(String.init)
            while segs.count > 1, containers.contains(segs[0].lowercased()) { segs.removeFirst() }
            p = segs.joined(separator: "/")
        }
        return p
    }

    // MARK: - tool schemas (Claude-native names so the primary model uses them fluently)

    static func anthropicTools(_ s: AppSettings) -> [[String: Any]] {
        var t: [[String: Any]] = [
            ["name": "Read", "description": "Read a file's full contents.",
             "input_schema": ["type": "object", "properties": ["file_path": ["type": "string", "description": "Path relative to the project root."]], "required": ["file_path"]]],
            ["name": "Write", "description": "Create a new file or fully overwrite an existing one. Provide the complete content.",
             "input_schema": ["type": "object", "properties": ["file_path": ["type": "string"], "content": ["type": "string"]], "required": ["file_path", "content"]]],
            ["name": "Edit", "description": "Replace an exact, verbatim string in an existing file. `old_string` must match the file exactly (including whitespace) and be unique enough to locate the spot.",
             "input_schema": ["type": "object", "properties": ["file_path": ["type": "string"], "old_string": ["type": "string"], "new_string": ["type": "string"]], "required": ["file_path", "old_string", "new_string"]]],
            ["name": "list_files", "description": "List every file in the project (path · line count · first line).",
             "input_schema": ["type": "object", "properties": [:]]],
        ]
        if s.allowCommands {
            t.append(["name": "Bash", "description": "Run a shell command in the project directory (install deps, run tests, git, build, start a dev server).",
                      "input_schema": ["type": "object", "properties": ["command": ["type": "string"]], "required": ["command"]]])
        }
        return t
    }

    static func openAITools(_ s: AppSettings) -> [[String: Any]] {
        anthropicTools(s).map { spec in
            ["type": "function", "function": ["name": spec["name"]!, "description": spec["description"]!, "parameters": spec["input_schema"]!]]
        }
    }
}
