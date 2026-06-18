import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// The app's brain + view-model. Owns the live conversation, drives solo / collab
/// orchestration against the provider engine, and exposes observable state the SwiftUI
/// views bind to. Ported from studio/src/main/index.ts (the Electron main process).
@MainActor
@Observable
final class AppController {
    // ---- observable UI state ----
    var messages: [ChatMessage] = []
    var busy = BusyState()
    var activity = ActivityState()
    var project = ProjectInfo.none
    var mode: Mode = .solo
    /// Per-lane selected model id ("" = provider default).
    var models: [AgentKind: String] = [.claude: "", .codex: ""]
    var modelOptions: [AgentKind: [ModelOption]] = [.claude: [], .codex: []]

    let settingsStore = SettingsStore()
    private let history = HistoryStore.shared

    /// Connection state per backend; session-scoped (not persisted). Used for BOTH app-login
    /// and api-key mode — a lane is only "ready" after the user clicks Connect (which, in key
    /// mode, validates the key against the provider). Filling a key alone does NOT connect.
    /// Connection state is per-LANE (left = .claude pane, right = .codex pane): the two lanes connect
    /// independently, each with its own key / base URL / login — even when they use the same model.
    var sessionAuth: [AgentKind: AuthStatus] = [.claude: .disconnected, .codex: .disconnected]
    var connecting: [AgentKind: Bool] = [.claude: false, .codex: false]

    /// Content checkpoints for the open project (R1: change preview + one-click rollback),
    /// newest first. Refreshed after every write turn and on project open. See SnapshotStore.
    var checkpoints: [SnapshotStore.Meta] = []
    var currentCheckpointId: String?   // the checkpoint disk currently reflects (HEAD)
    var rollingBack = false

    /// R2: one-click run — detected plan + live process status/logs/URL for the open project.
    var run = RunState()
    private var runTask: Task<Void, Never>?
    private var runGen = 0

    /// R3: runtime/visual problems detected while the project runs, + self-heal state.
    var runIssues: [RunIssue] = []
    var healing = false
    private let maxHealRounds = 2

    /// R4: cost metering — day-bucketed token/spend ledger for BYO-key API usage.
    var usage = UsageLedger()

    /// R5: guided start — a goal to drop into the planner composer when a model isn't connected yet.
    var composerSeed = ""

    // ---- internal orchestration state ----
    private var convo: [AgentKind: [LLMMessage]] = [.claude: [], .codex: []] // model-visible history per lane (HTTP/key mode)
    private var claudeSessions: [AgentKind: String] = [:] // claude --resume ids (app mode)
    private var codexThreads: [AgentKind: String] = [:]   // codex resume thread ids (app mode)
    private var intervene: [AgentKind: String] = [.claude: "", .codex: ""]
    private var runners: [AgentKind: Task<Void, Never>] = [:]
    private var collabRunner: Task<Void, Never>?
    private var cancelOrchestration = false
    private let maxRevise = 3

    private var msgSeq = 0
    private var msgN: [String: Int] = [:]

    init() {
        mode = .solo
        // Nothing async here — the window renders instantly. Model lists + CLI-login
        // detection (both spawn subprocesses) run from RootView's `.task`, after first paint.
    }

    /// Background startup work, kicked off after the first frame (see RootView).
    /// Note: connections start DISCONNECTED — the user connects manually via the header button.
    func startup() async {
        usage = await offMain { CostStore.load() }
        // Warm the login-shell env/PATH off-main so the first CLI connect/turn isn't blocked on it.
        Task.detached(priority: .utility) { _ = PathResolver.loginEnv; _ = PathResolver.path }
        await loadModels()
    }

    var settings: AppSettings { settingsStore.settings }

    // MARK: - derived readiness

    func backend(of kind: AgentKind) -> Backend { settings.backend(for: lane(of: kind)) }

    /// Pane → lane: left pane (.claude) = master, right pane (.codex) = slave.
    func lane(of kind: AgentKind) -> Lane { kind == .claude ? .master : .slave }

    /// A lane is ready only after a successful Connect (CLI login, or a validated API key).
    /// Filling in a key is NOT enough — the user must click Connect.
    func laneReady(_ kind: AgentKind) -> Bool {
        sessionAuth[kind]?.connected ?? false
    }

    func status(of kind: AgentKind) -> AuthStatus {
        sessionAuth[kind] ?? .disconnected
    }

    /// Set/replace a lane's API key. Entering or changing the key drops any existing
    /// connection so the user must click Connect again (which re-validates the key).
    func setApiKey(_ kind: AgentKind, _ v: String) {
        let l = lane(of: kind)
        guard v != settings.apiKeys[l] else { return } // no-op (e.g. a field re-commit on blur) must NOT disconnect
        settingsStore.update { $0.apiKeys[l] = v }
        sessionAuth[kind] = .disconnected // the key actually changed → require a fresh Connect
    }

    /// Set a lane's custom API base URL. Changing the endpoint drops the connection.
    func setBaseURL(_ kind: AgentKind, _ v: String) {
        let l = lane(of: kind)
        guard v != settings.baseURLs[l] else { return }
        settingsStore.update { $0.baseURLs[l] = v }
        sessionAuth[kind] = .disconnected
    }

    /// Toggle "use our default base URL" for a lane. Changing it drops the connection.
    func setUseDefaultBaseURL(_ kind: AgentKind, _ on: Bool) {
        let l = lane(of: kind)
        guard on != settings.useDefaultBaseURL[l] else { return }
        settingsStore.update { $0.useDefaultBaseURL[l] = on }
        sessionAuth[kind] = .disconnected
    }

    // MARK: - app-mode (CLI login) connect / disconnect

    /// Connect a lane. In key mode this VALIDATES the API key against the provider and only
    /// marks connected if it works; in app mode it checks/runs the CLI login. Each lane (left/right)
    /// connects independently, even when both use the same model.
    func connect(_ kind: AgentKind) {
        let l = lane(of: kind)
        let b = backend(of: kind)
        let method = settings.connectMethod(for: l)
        connecting[kind] = true

        if method == .key {
            Task {
                defer { connecting[kind] = false }
                // Lazily read the saved key from the Keychain (off-main). This is where the
                // one-time Keychain access prompt appears — in context on Connect, not at launch.
                var key = settings.apiKey(for: l)
                if key.isEmpty {
                    key = await Task.detached { KeychainStore.get(l) }.value
                    if !key.isEmpty { settingsStore.loadKeyInMemory(l, key) }
                }
                guard !key.isEmpty else {
                    sessionAuth[kind] = .disconnected
                    _ = post(.system, .error, tr("请先填写 \(b.displayName) 的 API Key。", "Enter the \(b.displayName) API key first."), false, nil, kind, nil)
                    return
                }
                switch await LLMEngine.validateKey(lane: l, key: key, settings: settings) {
                case .ok:
                    sessionAuth[kind] = AuthStatus(connected: true, detail: tr("API Key 已验证", "key validated"))
                    _ = post(.system, .text, tr("✅ \(b.displayName) 连接成功（API Key 验证通过）。", "✅ \(b.displayName) connected (API key validated)."), false, nil, kind, nil)
                    await loadModels(only: kind)
                case .unverified:
                    // The endpoint didn't answer /models (common with custom proxies). Don't block.
                    sessionAuth[kind] = AuthStatus(connected: true, detail: tr("未验证", "unverified"))
                    _ = post(.system, .text, tr("⚠️ \(b.displayName) 已连接，但无法自动验证（端点未返回 /models）。若发送失败，请检查 API Key 与 Base URL。",
                                                "⚠️ \(b.displayName) connected, but couldn't auto-validate (endpoint has no /models). If sending fails, check the API key and base URL."), false, nil, kind, nil)
                    await loadModels(only: kind)
                case .authFailed:
                    sessionAuth[kind] = .disconnected
                    _ = post(.system, .error, tr("❌ \(b.displayName) 连接失败：API Key 被拒绝（401/403），请检查后重试。", "❌ \(b.displayName) failed: API key rejected (401/403). Check it and retry."), false, nil, kind, nil)
                }
            }
            return
        }

        // app mode (CLI login) — claude / codex backends only
        guard b == .claude || b == .codex else { connecting[kind] = false; return }
        Task {
            defer { connecting[kind] = false }
            let cwd = project.cwd ?? NSHomeDirectory()
            let s = settings
            let existing = await AgentAuth.status(backend: b, lane: l, cwd: cwd, settings: s)
            if existing.connected {
                sessionAuth[kind] = existing
                _ = post(.system, .text, tr("✅ \(b.displayName) 已连接（复用本机登录态）。", "✅ \(b.displayName) connected (reusing local CLI login)."), false, nil, kind, nil)
            } else {
                let st = await AgentAuth.login(backend: b, lane: l, cwd: cwd, settings: s) { url in
                    Task { @MainActor in
                        _ = self.post(.system, .text, self.tr("如果浏览器没有自动打开，请手动访问以下链接完成 \(b.displayName) 登录：\n\(url)", "If the browser didn't open, visit this link to finish \(b.displayName) login:\n\(url)"), false, nil, kind, nil)
                    }
                }
                sessionAuth[kind] = st
                _ = post(.system, st.connected ? .text : .error,
                         st.connected ? tr("✅ \(b.displayName) 登录成功。", "✅ \(b.displayName) login succeeded.") : tr("❌ \(b.displayName) 登录未完成。", "❌ \(b.displayName) login not completed."), false, nil, kind, nil)
            }
            await loadModels(only: kind)
        }
    }

    /// Disconnect a lane: forget the in-app connection (keeps the API key / CLI login).
    func disconnect(_ kind: AgentKind) {
        sessionAuth[kind] = .disconnected
    }

    /// v1.1 — run a connection self-check for a lane and return a plain-language checklist.
    func diagnose(_ kind: AgentKind) async -> [DiagnosticItem] {
        let l = lang
        let lane = lane(of: kind)
        let b = backend(of: kind)
        let method = settings.connectMethod(for: lane)
        var items: [DiagnosticItem] = []

        items.append(.init(status: .info, title: l.t("当前配置", "Setup"),
                           detail: "\(b.displayName) · " + (method == .key ? l.t("API Key 模式", "API-key mode") : l.t("本机登录模式", "Local CLI login")),
                           fix: nil))

        if method == .key {
            var key = settings.apiKey(for: lane)
            if key.isEmpty { key = await offMain { KeychainStore.get(lane) } }
            guard !key.isEmpty else {
                items.append(.init(status: .fail, title: l.t("API Key", "API key"),
                                   detail: l.t("还没填写", "Not entered"),
                                   fix: l.t("在本栏顶部填入 \(b.displayName) 的 API Key", "Enter the \(b.displayName) API key in this pane's header")))
                return items
            }
            items.append(.init(status: .ok, title: l.t("API Key", "API key"), detail: l.t("已填写", "Provided"), fix: nil))

            let s = settings
            switch await LLMEngine.validateKey(lane: lane, key: key, settings: s) {
            case .ok:
                items.append(.init(status: .ok, title: l.t("连接验证", "Connection"),
                                   detail: l.t("Key 与端点验证通过", "Key + endpoint verified"), fix: nil))
            case .authFailed:
                items.append(.init(status: .fail, title: l.t("连接验证", "Connection"),
                                   detail: l.t("Key 被拒绝(401/403)", "Key rejected (401/403)"),
                                   fix: l.t("检查 Key 是否正确、是否有效/有额度", "Check the key is correct, active, and has quota")))
            case .unverified:
                let base = s.effectiveBaseURL(for: lane)
                let session = ProxyConfig.session(settings: s, lane: lane, direct: b == .deepseek)
                if await Diagnostics.reachable(base, session: session) {
                    items.append(.init(status: .warn, title: l.t("连接验证", "Connection"),
                                       detail: l.t("端点没返回 /models(常见于自定义中转)", "Endpoint has no /models (common with relays)"),
                                       fix: l.t("能连上但没法自动验证;若发送失败,核对 Base URL 与 Key", "Reachable but can't auto-verify; if sending fails, check base URL and key")))
                } else {
                    items.append(.init(status: .fail, title: l.t("网络", "Network"),
                                       detail: l.t("连不上 \(base)", "Can't reach \(base)"),
                                       fix: l.t("检查网络/代理,或更换 Base URL", "Check network/proxy, or change the base URL")))
                }
            }
        } else {
            let bin = b == .claude ? "claude" : "codex"
            let path = await offMain { PathResolver.resolve(bin) }
            guard let path else {
                items.append(.init(status: .fail, title: l.t("命令行工具", "CLI tool"),
                                   detail: l.t("没找到 \(bin)(未安装或不在 PATH)", "\(bin) not found (not installed / not on PATH)"),
                                   fix: l.t("先安装并登录 \(bin) 命令行工具", "Install and log in to the \(bin) CLI first")))
                return items
            }
            items.append(.init(status: .ok, title: l.t("命令行工具", "CLI tool"), detail: "\(bin) ✓", fix: path))

            let cwd = project.cwd ?? NSHomeDirectory()
            let s = settings
            let st = await AgentAuth.status(backend: b, lane: lane, cwd: cwd, settings: s)
            if st.connected {
                items.append(.init(status: .ok, title: l.t("登录态", "Login"),
                                   detail: st.detail ?? l.t("已登录", "Logged in"), fix: nil))
            } else {
                items.append(.init(status: .fail, title: l.t("登录态", "Login"),
                                   detail: l.t("\(bin) 未登录", "\(bin) not logged in"),
                                   fix: l.t("在终端运行 `\(bin) login` 登录后重试", "Run `\(bin) login` in Terminal, then retry")))
            }
            if let socks = await offMain({ Diagnostics.socksProxyInEnv() }) {
                items.append(.init(status: .warn, title: l.t("代理类型", "Proxy type"),
                                   detail: l.t("检测到 SOCKS 代理:\(socks)", "SOCKS proxy detected: \(socks)"),
                                   fix: l.t("CLI 不支持 SOCKS;在 设置→网络代理→自定义 填一个 HTTP 代理", "CLIs can't use SOCKS — set a custom HTTP proxy in Settings → Network proxy")))
            }
        }
        return items
    }
    var collab: Bool { mode == .collab }
    var anyBusy: Bool { busy.any }

    var claudeMessages: [ChatMessage] { messages.filter { $0.lane == .claude } }
    var codexMessages: [ChatMessage] { messages.filter { $0.lane == .codex } }

    // MARK: - public actions (called from the UI)

    func send(_ text: String, target: AgentKind) {
        let trimmed = text.trimmed
        guard !trimmed.isEmpty else { return }

        guard project.cwd != nil else {
            _ = post(.system, .error, tr("请先选择一个项目文件夹。", "Choose a project folder first."), false, nil, target, nil)
            return
        }

        if budgetBlocked(target) { return }

        // "记住 …" → store a fact in curated memory instead of running a turn.
        if let fact = Prompts.rememberFact(in: trimmed) {
            MemoryStore.appendCurated(project.cwd, fact)
            _ = post(.user, .text, trimmed, false, nil, target, nil)
            let scope = project.cwd != nil ? tr("项目记忆", "project memory") : tr("全局记忆", "global memory")
            _ = post(.system, .text, tr("🧠 已记住（\(scope)）：\(fact)", "🧠 Saved to \(scope): \(fact)"), false, nil, target, nil)
            return
        }

        // 随时插话: if something is running, inject instead of starting fresh.
        let running = collab ? busy.any : busy[target]
        if running {
            let lane: AgentKind = collab ? .claude : target
            _ = post(.user, .text, trimmed, false, nil, lane, nil)
            if collab {
                intervene[.claude, default: ""] += (intervene[.claude]!.isEmpty ? "" : "\n") + trimmed
                intervene[.codex, default: ""] += (intervene[.codex]!.isEmpty ? "" : "\n") + trimmed
            } else {
                intervene[target, default: ""] += (intervene[target]!.isEmpty ? "" : "\n") + trimmed
            }
            return
        }

        if collab {
            collabRunner = Task { await self.runOrchestration(trimmed) }
        } else {
            runners[target] = Task { await self.handleSolo(trimmed, target: target) }
        }
    }

    func abort(_ target: AgentKind) {
        if collab {
            cancelOrchestration = true
            collabRunner?.cancel()
            runners.values.forEach { $0.cancel() }
        } else {
            runners[target]?.cancel()
        }
    }

    func setMode(_ m: Mode) {
        mode = m
        Task { await history.setMode(m) }
    }

    func setModel(_ kind: AgentKind, _ id: String) { models[kind] = id }

    func changeBackend(_ kind: AgentKind, _ b: Backend) {
        settingsStore.update {
            if kind == .claude { $0.masterBackend = b } else { $0.slaveBackend = b }
        }
        models[kind] = "" // reset model when the backend changes
        sessionAuth[kind] = .disconnected // different provider → reconnect this lane
        Task { await loadModels(only: kind) }
    }

    // MARK: - lane option (combined backend + method) & language

    var lang: Lang { settings.language }
    func tr(_ zh: String, _ en: String) -> String { settings.language.t(zh, en) }
    func toggleLanguage() { settingsStore.update { $0.language = $0.language.toggled } }

    /// The single combined choice currently selected for a lane.
    func laneOption(_ kind: AgentKind) -> LaneOption {
        let l = lane(of: kind)
        return LaneOption.from(backend: settings.backend(for: l), method: settings.connectMethod(for: l))
    }

    /// Pick a lane's backend + connect method in one go (the header/settings dropdown).
    func selectLaneOption(_ kind: AgentKind, _ opt: LaneOption) {
        let l = lane(of: kind)
        settingsStore.update {
            if kind == .claude { $0.masterBackend = opt.backend } else { $0.slaveBackend = opt.backend }
            $0.connectMethod[l] = opt.method
        }
        models[kind] = ""
        sessionAuth[kind] = .disconnected
        Task { await loadModels(only: kind) }
    }

    // MARK: - project

    func pickProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "选择项目"
        if panel.runModal() == .OK, let url = panel.url {
            setProject(url)
        }
    }

    func setProject(_ url: URL) {
        stopRun()
        run = RunState()
        let resolved = url.resolvingSymlinksInPath()
        let cwd = resolved.path
        project = ProjectInfo(cwd: cwd, name: resolved.lastPathComponent)
        convo = [.claude: [], .codex: []]
        messages = []
        checkpoints = []
        Task { await detectRunPlan() }
        Task { await history.startSession(projectCwd: cwd, projectName: resolved.lastPathComponent, mode: mode) }
        // Seed an initial checkpoint if the project has none yet, then load the timeline.
        let initLabel = tr("初始状态", "Initial state")
        Task {
            let hasHead = await offMain { SnapshotStore.head(cwd) != nil }
            if !hasHead {
                _ = await offMain { SnapshotStore.snapshot(cwd: cwd, label: initLabel) }
            }
            await refreshCheckpoints()
        }
    }

    // MARK: - resume a saved session

    func resume(_ session: Session, focus: String? = nil) {
        abort(.claude); abort(.codex)
        cancelOrchestration = false
        project = ProjectInfo(cwd: session.projectCwd, name: session.projectName)
        mode = session.mode
        messages = session.messages
        convo = [.claude: [], .codex: []] // fresh model context; the transcript is shown but not replayed
        checkpoints = []
        stopRun()
        run = RunState()
        Task { await history.adoptSession(session) }
        Task { await refreshCheckpoints() }
        Task { await detectRunPlan() }
    }

    // MARK: - orchestration

    private func handleSolo(_ text: String, target: AgentKind) async {
        _ = post(.user, .text, text, false, nil, target, nil)
        var next: String? = text
        var lastReply = ""
        while let n = next {
            if Task.isCancelled { break }
            // Solo mode: the lane works alone, so it owns the WHOLE job (understand → implement →
            // edit files), not just planning/review. Both lanes write.
            let res = await laneTurn(target, prompt: n, system: Prompts.soloAgent(lang),
                                     phase: tr("处理中", "Working"), write: true)
            if !res.ok { break }
            lastReply = res.text
            next = intervene[target]?.nonEmpty
            intervene[target] = ""
        }
        if !lastReply.isEmpty {
            await autoExtractMemory("用户：\(text)\n助手：\(lastReply)", lane: lane(of: target))
        }
    }

    private func runOrchestration(_ goal: String) async {
        cancelOrchestration = false
        _ = post(.user, .text, goal, false, nil, .claude, nil)

        let plan = await laneTurn(.claude, prompt: withIntervene(Prompts.plan(goal: goal, lang), .claude),
                                  system: Prompts.planner(lang), phase: tr("规划中", "Planning"), write: false)
        if stopped() || !plan.ok { return }

        let cwd = project.cwd ?? ""
        let before = await offMain { ProjectFiles.snapshot(cwd) }
        let exec = await laneTurn(.codex, prompt: withIntervene(Prompts.execute(plan: plan.text, lang), .codex),
                                  system: Prompts.executor(lang), phase: tr("执行中", "Working"), write: true)
        if stopped() || !exec.ok { return }

        for iter in 0..<maxRevise {
            let diff = await offMain { ProjectFiles.changesSince(before, cwd: cwd) }
            let review = await laneTurn(.claude, prompt: withIntervene(Prompts.review(goal: goal, diff: diff, lang), .claude),
                                        system: Prompts.reviewer(lang), phase: tr("审查中", "Reviewing"), write: false)
            if stopped() || !review.ok { return }
            if Prompts.verdictPass(review.text) {
                _ = post(.system, .text, tr("✅ 完成：\(backend(of: .claude).displayName) 审查通过。", "✅ Done: \(backend(of: .claude).displayName) approved the review."), false, nil, .claude, nil)
                await autoExtractMemory("目标：\(goal)\n计划：\(plan.text)\n审查：\(review.text)", lane: .master)
                return
            }
            if iter == maxRevise - 1 {
                _ = post(.system, .text, tr("已自动修改 \(maxRevise) 轮仍未通过，请人工查看或补充说明。", "Auto-revised \(maxRevise) rounds without passing — please review or add guidance."), false, nil, .claude, nil)
                await autoExtractMemory("目标：\(goal)\n计划：\(plan.text)\n最近审查：\(review.text)", lane: .master)
                return
            }
            let revise = await laneTurn(.codex, prompt: withIntervene(Prompts.revise(feedback: review.text, lang), .codex),
                                        system: Prompts.executor(lang), phase: tr("修订中", "Revising"), write: true)
            if stopped() || !revise.ok { return }
        }
    }

    private func stopped() -> Bool {
        if cancelOrchestration || Task.isCancelled {
            _ = post(.system, .text, tr("⏹ 已停止。", "⏹ Stopped."), false, nil, .claude, nil)
            return true
        }
        return false
    }

    /// One lane's streaming turn, dispatched to its configured backend.
    private func laneTurn(_ kind: AgentKind, prompt: String, system: String, phase: String, write: Bool) async -> (ok: Bool, text: String) {
        let lane: Lane = kind == .claude ? .master : .slave
        let b = settings.backend(for: lane)
        let name = b.displayName
        let role: Role = kind == .claude ? .claude : .codex
        let l = lang
        let pid = post(role, write ? .progress : .text, write ? "\(name) " + l.t("正在处理…", "is working…") : "", true, nil, kind, name)
        setActivity(kind, phase)

        let method = settings.connectMethod(for: lane)
        let useCLI = method == .app && (b == .claude || b == .codex)

        let model = (models[kind] ?? "").nonEmpty
        let cwd0 = project.cwd
        let mem = await offMain { MemoryStore.context(cwd0) }
        // HTTP write turns run a tool-use agent loop (read/write/edit/run); CLI write turns let the CLI edit files itself.
        let baseSystem = (write && !useCLI) ? Prompts.agentExecutor(l) : system
        // Inject the real backend/model so the assistant can disclose its identity truthfully.
        let withIdentity = "\(baseSystem)\n\n\(Prompts.identity(backend: b, model: model ?? LLMModels.defaultModel(b), l))"
        let sys = mem.isEmpty ? withIdentity : "\(mem)\n\n\(withIdentity)"
        var full = ""
        var failed: String?
        // Coalesce streaming UI updates: keep `full` current every token (cheap), but only re-paint
        // the message on a slow cadence so a fast stream lands in a few big chunks instead of
        // "typing" character-by-character. The first chunk shows immediately; the final, complete
        // text is always posted after the loop.
        let flushInterval: TimeInterval = 5.0
        var lastFlush = Date()   // first chunk lands at +5s; until then the message shows "stream…"
        let onDelta: (String) -> Void = { text in
            full = text
            let now = Date()
            if now.timeIntervalSince(lastFlush) >= flushInterval {
                lastFlush = now
                _ = self.post(role, write ? .progress : .text, text, true, pid, kind, name)
            }
        }
        let onStatus: (String) -> Void = { self.setActivity(kind, $0) }

        if useCLI, let cwd = project.cwd {
            // ---- app mode: drive the local CLI, reusing its login (no API key) ----
            if b == .claude {
                let r = await ClaudeCLI.run(prompt: prompt, cwd: cwd, system: sys, model: model, write: write,
                                            resumeId: claudeSessions[kind], lane: lane, settings: settings)
                if let id = r.resumeId { claudeSessions[kind] = id }
                full = r.text; failed = r.ok ? nil : (r.error ?? "claude error")
                if r.ok { onDelta(full) } // surface the (non-streamed) result
            } else {
                do {
                    for try await ev in CodexCLI.run(prompt: prompt, cwd: cwd, sandbox: write ? .workspaceWrite : .readOnly,
                                                     model: model, threadId: codexThreads[kind], lane: lane, settings: settings) {
                        if Task.isCancelled { failed = l.t("已停止", "Stopped"); break }
                        switch ev {
                        case .delta(let t): onDelta(t)
                        case .status(let s): onStatus(s)
                        case .done(let r):
                            if let id = r.resumeId { codexThreads[kind] = id }
                            full = r.text; failed = r.ok ? nil : (r.error ?? "codex error")
                        }
                    }
                } catch {
                    failed = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                }
            }
        } else if write, let cwd = project.cwd {
            // ---- key mode + WRITE: a real tool-use agent edits files (and runs commands when allowed),
            // iterating until done — instead of emitting one whole-file blob. Plan B: the Anthropic
            // lane drives the official Claude Agent SDK (full harness) when the Node sidecar is
            // available; OpenAI/DeepSeek (and SDK-unavailable Claude) use the built-in AgentEngine.
            // Returns early; the shared block below serves non-write key turns and the CLI path.
            let mdl = model ?? LLMModels.defaultModel(b)
            let ok: Bool, replyText: String, inTok: Int, outTok: Int, changedFiles: [String]
            var errMsg: String?
            let sdk = (b == .claude && settings.useAgentSDK) ? AgentSDKClient.locate() : nil
            if let sdk, AgentSDKClient.isInstalled(script: sdk.script) {
                let r = await AgentSDKClient.run(
                    node: sdk.node, script: sdk.script, lane: lane, model: mdl, system: sys, prompt: prompt,
                    cwd: cwd, settings: settings,
                    onText: { t in Task { @MainActor in _ = self.post(role, .progress, t, true, pid, kind, name) } },
                    onActivity: { s in Task { @MainActor in self.setActivity(kind, s) } })
                (ok, replyText, inTok, outTok, errMsg, changedFiles) = (r.ok, r.text, r.input, r.output, r.error, r.changed)
            } else {
                let r = await AgentEngine.run(lane: lane, backend: b, model: mdl, system: sys, prompt: prompt,
                                              cwd: cwd, settings: settings,
                                              onActivity: { s in Task { @MainActor in self.setActivity(kind, s) } })
                (ok, replyText, inTok, outTok, errMsg, changedFiles) = (r.ok, r.text, r.input, r.output, r.error, r.changed)
            }
            recordUsage(backend: b, model: mdl, input: inTok, output: outTok)
            setActivity(kind, "")
            guard ok else {
                _ = post(.system, .error, errMsg ?? l.t("出错了", "Something went wrong"), false, pid, kind, name)
                return (false, "")
            }
            var seen = Set<String>()
            let changed = changedFiles.filter { seen.insert($0).inserted }
            var summary = ""
            if !changed.isEmpty {
                summary = l.t("\n\n📄 已更新 \(changed.count) 个文件：\(changed.joined(separator: "、"))",
                              "\n\n📄 Updated \(changed.count) file(s): \(changed.joined(separator: ", "))")
            } else {
                summary = l.t("\n\n（本次没有改动文件）", "\n\n(No files were changed.)")
            }
            let display = (replyText.trimmed.isEmpty ? l.t("（已处理）", "(done)") : replyText) + summary
            _ = post(role, .text, display, false, pid, kind, name)
            if !changed.isEmpty { await captureCheckpoint(checkpointLabel(replyText.trimmed.isEmpty ? prompt : replyText, l), cwd: cwd) }
            return (true, display)
        } else {
            // ---- key mode: direct provider HTTP API (planner / reviewer turns; streamed) ----
            let userMsg = LLMMessage(role: .user, content: prompt)
            // Cap the sent history so a long session can't grow the context past the model limit.
            let history = Array((convo[kind] ?? []).suffix(40))
            let req = ChatRequest(backend: b, lane: lane, model: model, systemPrompt: sys, messages: history + [userMsg])
            var inTok = 0, outTok = 0
            do {
                for try await ev in LLMEngine.stream(req, settings: settings) {
                    if Task.isCancelled { failed = l.t("已停止", "Stopped"); break }
                    switch ev {
                    case .delta(let d): full += d; onDelta(full)
                    case .status(let s): onStatus(s)
                    case .usage(let i, let o): inTok = i; outTok = o
                    }
                }
            } catch {
                failed = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            }
            recordUsage(backend: b, model: model ?? LLMModels.defaultModel(b), input: inTok, output: outTok)
            if failed == nil && !full.isEmpty {
                convo[kind, default: []].append(userMsg)
                convo[kind, default: []].append(LLMMessage(role: .assistant, content: full))
            }
        }

        let ok = failed == nil && !full.isEmpty
        if ok {
            // File writing applies only to the HTTP path — the CLI already wrote files itself.
            // Supports both whole-file (<<<FILE>>>) and incremental search/replace (<<<EDIT>>>).
            if write, !useCLI, let cwd = project.cwd {
                setActivity(kind, l.t("写入文件中", "Writing files"))
                let (prose, written, failed): (String, [String], [String]) = await offMain {
                    let c = ProjectFiles.parseChanges(full)
                    let w = ProjectFiles.applyFiles(cwd: cwd, files: c.files)
                    let e = ProjectFiles.applyEdits(cwd: cwd, edits: c.edits)
                    return (c.prose, w + e.applied, e.failed)
                }
                setActivity(kind, "")
                var summary = ""
                if !written.isEmpty {
                    summary += l.t("\n\n📄 已更新 \(written.count) 个文件：\(written.joined(separator: "、"))",
                                   "\n\n📄 Updated \(written.count) file(s): \(written.joined(separator: ", "))")
                }
                if !failed.isEmpty {
                    summary += l.t("\n\n⚠️ \(failed.count) 处修改没对上原文(文件未改)：\(failed.joined(separator: "、"))——可让执行方改用整文件输出。",
                                   "\n\n⚠️ \(failed.count) edit(s) didn't match the original (unchanged): \(failed.joined(separator: ", ")) — ask the executor to output the whole file instead.")
                }
                if written.isEmpty && failed.isEmpty {
                    summary = l.t("\n\n（未解析到文件改动——请让执行方按 <<<FILE>>> 或 <<<EDIT>>> 格式输出）",
                                  "\n\n(No file changes parsed — ask the executor to use the <<<FILE>>> or <<<EDIT>>> format.)")
                }
                let display = (prose.isEmpty ? l.t("（已处理）", "(done)") : prose) + summary
                _ = post(role, .text, display, false, pid, kind, name)
                if !written.isEmpty { await captureCheckpoint(checkpointLabel(prose.isEmpty ? full : prose, l), cwd: cwd) }
                return (true, display)
            }
            setActivity(kind, "")
            _ = post(role, .text, full, false, pid, kind, name)
            // CLI write path already edited files itself (HTTP write returned above).
            if write, let cwd = project.cwd { await captureCheckpoint(checkpointLabel(full, l), cwd: cwd) }
        } else {
            setActivity(kind, "")
            _ = post(.system, .error, failed ?? l.t("出错了", "Something went wrong"), false, pid, kind, name)
        }
        return (ok, full)
    }

    private func withIntervene(_ prompt: String, _ lane: AgentKind) -> String {
        guard let extra = intervene[lane]?.nonEmpty else { return prompt }
        intervene[lane] = ""
        return tr("（用户临时补充指令，请务必优先考虑）：\(extra)\n\n\(prompt)",
                  "(User added instructions — prioritize these): \(extra)\n\n\(prompt)")
    }

    // MARK: - checkpoints (R1: change preview + rollback)

    /// A short, human label for a checkpoint, taken from the executor's own summary line.
    private func checkpointLabel(_ text: String, _ l: Lang) -> String {
        let firstLine = text.split(separator: "\n").map(String.init).first?.trimmed ?? ""
        let cleaned = firstLine.replacingOccurrences(of: "📄", with: "").trimmed
        return cleaned.isEmpty ? l.t("一次改动", "A change") : String(cleaned.prefix(48))
    }

    /// Snapshot the project after a successful write turn, prune old checkpoints, refresh the timeline.
    func captureCheckpoint(_ label: String, cwd: String) async {
        let meta = await offMain { SnapshotStore.snapshot(cwd: cwd, label: label) }
        await offMain { SnapshotStore.prune(cwd: cwd) }
        if meta != nil { await refreshCheckpoints() }
        if !run.isActive { await detectRunPlan() } // the AI may have just made the project runnable
    }

    /// Reload the checkpoint timeline (and current HEAD) from disk for the open project.
    func refreshCheckpoints() async {
        let cwd = project.cwd
        let (list, head): ([SnapshotStore.Meta], String?) = await offMain {
            guard let cwd else { return ([], nil) }
            return (SnapshotStore.list(cwd: cwd), SnapshotStore.head(cwd))
        }
        checkpoints = list
        currentCheckpointId = head
    }

    /// The files (with before/after content) that a given checkpoint changed vs its parent.
    func changes(for id: String) async -> [SnapshotStore.FileChange] {
        guard let cwd = project.cwd else { return [] }
        return await offMain { SnapshotStore.changes(cwd: cwd, id: id) }
    }

    /// Restore the project on disk to a checkpoint, then refresh and announce it in chat.
    func rollback(to id: String) async {
        guard let cwd = project.cwd, !rollingBack else { return }
        rollingBack = true
        setActivity(.codex, tr("回滚中", "Rolling back"))
        let ok = await offMain { SnapshotStore.restore(cwd: cwd, id: id) }
        setActivity(.codex, "")
        await refreshCheckpoints()
        rollingBack = false
        let label = checkpoints.first(where: { $0.id == id })?.label ?? ""
        if ok {
            _ = post(.system, .text, tr("⏪ 已回滚到「\(label)」。之后的改动已撤销。",
                                        "⏪ Rolled back to “\(label)”. Later changes were undone."), false, nil, .claude, nil)
        } else {
            _ = post(.system, .error, tr("回滚失败，请重试。", "Rollback failed, please try again."), false, nil, .claude, nil)
        }
    }

    // MARK: - runner (R2: one-click run)

    /// Re-detect how the open project should run (Node dev script / Python / static page).
    func detectRunPlan() async {
        guard let cwd = project.cwd else { run.plan = nil; return }
        run.plan = await offMain { ProjectRunner.detect(cwd: cwd) }
    }

    /// Start (or for a static page, simply preview) the project. No-op if a run is already active.
    func startRun() {
        guard let cwd = project.cwd, let plan = run.plan, runTask == nil else { return }
        let l = lang
        if plan.kind == .staticSite {
            run.status = .running
            run.url = nil
            run.logs = []
            run.message = l.t("静态页面，已直接预览。", "Static page — previewing directly.")
            return
        }
        guard let bin = plan.bin else {
            run.status = .failed
            run.message = l.t("没找到运行所需的命令（npm / python）。请先安装后重试。",
                              "Couldn't find the command to run (npm / python). Install it and retry.")
            return
        }
        run.logs = []
        run.url = nil
        runIssues = []
        runGen += 1
        let gen = runGen
        runTask = Task { await self.runLoop(cwd: cwd, plan: plan, bin: bin, gen: gen, l: l) }
    }

    /// Stop the running process (or static preview).
    func stopRun() {
        runGen += 1 // invalidate any in-flight finalize
        runTask?.cancel()
        runTask = nil
        if run.isActive {
            run.status = .stopped
            run.message = tr("已停止。", "Stopped.")
        }
        run.url = nil
    }

    private func runLoop(cwd: String, plan: ProjectRunner.Plan, bin: String, gen: Int, l: Lang) async {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = PathResolver.path
        env["BROWSER"] = "none"   // don't let dev servers pop a system browser
        env["FORCE_COLOR"] = "0"
        env["NO_COLOR"] = "1"

        // Install Node deps first if they're missing — non-coders won't have run `npm install`.
        if plan.kind == .node, plan.needsInstall, let pm = plan.packageManager {
            run.status = .installing
            run.message = l.t("正在安装依赖（首次运行较慢）…", "Installing dependencies (first run is slow)…")
            appendLog("$ \(pm) install")
            let installBin = PathResolver.resolve(pm) ?? bin
            let ok = await runToEnd(installBin, ["install"], cwd: cwd, env: env)
            guard gen == runGen else { return }
            if !ok {
                run.status = .failed
                run.message = l.t("依赖安装失败，请查看日志。", "Dependency install failed — see the log.")
                if gen == runGen { runTask = nil }
                return
            }
        }

        run.status = .starting
        run.message = l.t("正在启动…", "Starting…")
        appendLog("$ \(plan.label)")
        do {
            for try await ev in runProcess(bin, plan.args, cwd: cwd, env: env) {
                guard gen == runGen else { return }
                switch ev {
                case .line(let raw):
                    let line = ProjectRunner.stripANSI(raw)
                    appendLog(line)
                    if run.status == .starting { run.status = .running; run.message = l.t("运行中…", "Running…") }
                    if run.url == nil, let u = ProjectRunner.detectURL(in: line) {
                        run.url = u
                        run.message = l.t("运行中：", "Running: ") + u
                    }
                case .finished(let code, let err):
                    if !err.isEmpty {
                        for line in err.split(separator: "\n") { appendLog(ProjectRunner.stripANSI(String(line))) }
                    }
                    if code == 0 {
                        run.status = .stopped; run.message = l.t("已结束。", "Finished.")
                    } else {
                        run.status = .failed; run.message = l.t("退出码 \(code)，请查看日志。", "Exit code \(code) — see the log.")
                    }
                }
            }
        } catch {
            guard gen == runGen else { return }
            if Task.isCancelled || error is CancellationError {
                run.status = .stopped; run.message = l.t("已停止。", "Stopped.")
            } else {
                run.status = .failed
                run.message = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            }
        }
        if gen == runGen { runTask = nil }
    }

    private func runToEnd(_ bin: String, _ args: [String], cwd: String, env: [String: String]) async -> Bool {
        do {
            for try await ev in runProcess(bin, args, cwd: cwd, env: env) {
                switch ev {
                case .line(let l): appendLog(ProjectRunner.stripANSI(l))
                case .finished(let code, let err):
                    if !err.isEmpty { for line in err.split(separator: "\n") { appendLog(ProjectRunner.stripANSI(String(line))) } }
                    return code == 0
                }
            }
        } catch { appendLog("\(error)") }
        return false
    }

    private func appendLog(_ s: String) {
        run.logs.append(s)
        if run.logs.count > 800 { run.logs.removeFirst(run.logs.count - 800) }
        if let err = ProjectRunner.buildError(in: s) { addRunIssue(.build, err) }
    }

    // MARK: - R3: runtime/visual verification + self-heal

    /// Record a detected runtime/visual problem (deduped). Called from the preview web view bridge
    /// and the log scanner.
    func addRunIssue(_ kind: RunIssue.Kind, _ message: String) {
        let msg = message.trimmed
        guard !msg.isEmpty else { return }
        let id = "\(kind.rawValue)|\(msg.prefix(160))"
        guard !runIssues.contains(where: { $0.id == id }) else { return }
        runIssues.append(RunIssue(id: id, kind: kind, message: String(msg.prefix(600))))
        if runIssues.count > 50 { runIssues.removeFirst(runIssues.count - 50) }
    }

    func clearRunIssues() { runIssues = [] }

    /// One-click self-heal: feed the detected problems to the executor to fix, reload, and re-check —
    /// up to a couple of rounds, stopping as soon as the runtime is clean.
    func selfHeal() async {
        guard !healing, !runIssues.isEmpty, project.cwd != nil, laneReady(.codex), !busy.any else { return }
        if budgetBlocked(.codex) { return }
        healing = true
        defer { healing = false }
        let l = lang
        for round in 0..<maxHealRounds {
            let issues = runIssues
            if issues.isEmpty { break }
            let report = issues.map { "- [\($0.kind.label(l))] \($0.message)" }.joined(separator: "\n")
            _ = post(.system, .text, l.t("🩹 正在自动修复 \(issues.count) 个运行时问题…（第 \(round + 1) 轮）",
                                         "🩹 Auto-fixing \(issues.count) runtime issue(s)… (round \(round + 1))"),
                     false, nil, .codex, nil)
            let res = await laneTurn(.codex, prompt: withIntervene(Prompts.fixIssues(report: report, l), .codex),
                                     system: Prompts.executor(l), phase: l.t("修复中", "Fixing"), write: true)
            if !res.ok { break } // keep the issues visible so the user can see what went wrong
            // clear, reload the preview, and give it a few seconds to surface any fresh errors.
            clearRunIssues()
            run.reloadNonce &+= 1
            try? await Task.sleep(for: .seconds(3))
            if runIssues.isEmpty {
                _ = post(.system, .text, l.t("✅ 自动修复完成，未再检测到运行时报错。",
                                             "✅ Auto-fix complete — no runtime errors detected."), false, nil, .codex, nil)
                return
            }
        }
        if !runIssues.isEmpty {
            _ = post(.system, .text, l.t("仍有问题未解决，请在对话里补充说明，或手动查看。",
                                         "Some issues remain — add guidance in chat, or take a look manually."), false, nil, .codex, nil)
        }
    }

    /// The URL the run preview should show: a live dev-server URL, else a static file, else nil.
    func runPreviewURL() -> URL? {
        if let u = run.url, let url = URL(string: u) { return url }
        if run.plan?.kind == .staticSite, let entry = run.plan?.entryFile, let cwd = project.cwd {
            return URL(fileURLWithPath: cwd).appendingPathComponent(entry)
        }
        return nil
    }

    // MARK: - share / export (R6)

    var exporting = false

    /// Package the project into a ZIP and let the user save it somewhere, then reveal it in Finder.
    func exportProject() async {
        guard let cwd = project.cwd, !exporting else { return }
        exporting = true
        defer { exporting = false }
        let name = project.name ?? "project"
        let zip = await offMain { Exporter.makeZip(cwd: cwd, name: name) }
        guard let zip else {
            _ = post(.system, .error, tr("打包失败，请重试。", "Packaging failed, please try again."), false, nil, .claude, nil)
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(name).zip"
        panel.canCreateDirectories = true
        if let zipType = UTType(filenameExtension: "zip") { panel.allowedContentTypes = [zipType] }
        if panel.runModal() == .OK, let dest = panel.url {
            let ok = await offMain { Exporter.move(zip, to: dest) }
            if ok {
                NSWorkspace.shared.activateFileViewerSelecting([dest])
                _ = post(.system, .text, tr("✅ 已导出 ZIP：\(dest.lastPathComponent)", "✅ Exported ZIP: \(dest.lastPathComponent)"), false, nil, .claude, nil)
            } else {
                _ = post(.system, .error, tr("保存失败，请重试。", "Saving failed, please try again."), false, nil, .claude, nil)
            }
        } else {
            await offMain { try? FileManager.default.removeItem(at: zip.deletingLastPathComponent()) } // cancelled → clean temp
        }
    }

    /// Show the project folder in Finder.
    func revealProject() {
        guard let cwd = project.cwd else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: cwd)])
    }

    /// Open the project's static result (index.html) in the default browser, if there is one.
    func openResult() {
        guard let cwd = project.cwd, let url = Exporter.indexHTML(cwd) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Whether the project has a directly-openable static page.
    func hasOpenableResult() -> Bool {
        guard let cwd = project.cwd else { return false }
        return Exporter.indexHTML(cwd) != nil
    }

    // MARK: - guided start (R5)

    /// Kick off a guided build: ensure a project folder, lay down any template scaffold, then
    /// either run the build (if a model is connected) or seed the goal for the user to send.
    /// Returns false if the user cancelled folder selection (so the caller stays on the start screen).
    @discardableResult
    func startGuided(goal: String, files: [ProjectFiles.ParsedFile]) -> Bool {
        if project.cwd == nil {
            pickProject()                       // modal folder picker; sets project on OK
            guard project.cwd != nil else { return false } // cancelled
        }
        if let cwd = project.cwd, !files.isEmpty {
            let label = tr("模板初始化", "Template scaffold")
            let written = ProjectFiles.applyFiles(cwd: cwd, files: files)
            if !written.isEmpty {
                _ = post(.system, .text, tr("📄 已创建模板文件：\(written.joined(separator: "、"))",
                                            "📄 Created template files: \(written.joined(separator: ", "))"), false, nil, .claude, nil)
                Task { await captureCheckpoint(label, cwd: cwd); await detectRunPlan() }
            }
        }
        beginBuild(goal: goal)
        return true
    }

    /// Run the build for a goal (collab plan→execute→review), or seed it if no model is connected.
    func beginBuild(goal: String) {
        let goal = goal.trimmed
        guard !goal.isEmpty else { return }
        setMode(.collab)
        if laneReady(.claude) {
            send(goal, target: .claude)
        } else {
            composerSeed = goal
            _ = post(.system, .text,
                     tr("已把目标准备好。请在左栏右上角选择并连接一个模型，然后点发送即可开始制作。",
                        "Your goal is ready. Pick and connect a model in the left pane's header, then hit send to start."),
                     false, nil, .claude, nil)
        }
    }

    // MARK: - cost metering (R4)

    /// Record token usage for one HTTP API call and persist the ledger.
    func recordUsage(backend: Backend, model: String, input: Int, output: Int) {
        guard input > 0 || output > 0 else { return }
        let cost = Pricing.cost(backend: backend, model: model, input: input, output: output)
        var led = usage
        led.add(dayKey: CostStore.dayKey(), input: input, output: output, cost: cost)
        usage = led
        Task.detached(priority: .utility) { CostStore.save(led) }
    }

    func resetUsage() {
        usage = UsageLedger()
        Task.detached(priority: .utility) { CostStore.save(UsageLedger()) }
    }

    var costToday: Double { usage.cost(forPrefix: CostStore.dayKey()) }
    var costMonth: Double { usage.cost(forPrefix: CostStore.monthKey()) }
    var costTotal: Double { usage.total().cost }
    var tokensTotal: Int { let t = usage.total(); return t.input + t.output }

    /// Monthly budget (0 = off) and how close this month's spend is to it.
    var monthlyBudget: Double { settings.monthlyBudgetUSD }
    var budgetFraction: Double { monthlyBudget > 0 ? min(costMonth / monthlyBudget, 1) : 0 }
    var overBudget: Bool { monthlyBudget > 0 && costMonth >= monthlyBudget }

    /// Block a new turn when the monthly budget is spent. Returns true if blocked (and notifies).
    private func budgetBlocked(_ target: AgentKind) -> Bool {
        guard overBudget else { return false }
        _ = post(.system, .error,
                 tr("已达本月预算上限（约 $\(money(costMonth)) / $\(money(monthlyBudget))）。可在「设置」里调高或关闭预算。",
                    "Monthly budget reached (≈$\(money(costMonth)) / $\(money(monthlyBudget))). Raise or turn it off in Settings."),
                 false, nil, target, nil)
        return true
    }

    func money(_ v: Double) -> String { String(format: v < 1 ? "%.3f" : "%.2f", v) }

    // MARK: - memory extraction

    private func llmComplete(lane: Lane, prompt: String, system: String) async -> String {
        let backend = settings.backend(for: lane)
        let model = LLMModels.cheapModel(backend)
        let req = ChatRequest(backend: backend, lane: lane, model: model,
                              systemPrompt: system, messages: [LLMMessage(role: .user, content: prompt)])
        let r = await LLMEngine.complete(req, settings: settings)
        recordUsage(backend: backend, model: model, input: r.input, output: r.output)
        return r.ok ? r.text : ""
    }

    private func autoExtractMemory(_ transcript: String, lane: Lane) async {
        guard settings.autoMemory, !overBudget else { return }
        let cwd = project.cwd
        let curated = cwd != nil ? MemoryStore.getProject(cwd) : MemoryStore.getGlobal()
        let learned = cwd != nil ? MemoryStore.getProjectLearned(cwd) : MemoryStore.getGlobalLearned()
        let known = "\(curated)\n\(learned)".trimmed
        let prompt = tr(
            "已有记忆（不要重复其中已有的）：\n\(known.isEmpty ? "（空）" : known)\n\n本次对话：\n\(String(transcript.prefix(6000)))\n\n请只输出新增、值得长期记住的要点：",
            "Existing memory (don't repeat what's there):\n\(known.isEmpty ? "(empty)" : known)\n\nThis conversation:\n\(String(transcript.prefix(6000)))\n\nOutput only new points worth keeping long-term:")
        let text = await llmComplete(lane: lane, prompt: prompt, system: Prompts.memoryExtract(lang))
        let lines = text.split(separator: "\n").map {
            String($0).replacingOccurrences(of: "^[-*•\\d.、)\\s]+", with: "", options: .regularExpression).trimmed
        }.filter { !$0.isEmpty && $0 != "无" && $0.count > 2 }
        if !lines.isEmpty { MemoryStore.appendLearned(cwd, lines) }
    }

    func consolidate(scope: MemoryScope) async -> String {
        let cur = scope == .global ? MemoryStore.getGlobalLearned() : MemoryStore.getProjectLearned(project.cwd)
        guard !cur.trimmed.isEmpty else { return cur }
        let cleaned = await llmComplete(lane: .master,
                                        prompt: tr("请整理以下记忆：\n\n\(cur)", "Tidy these memory notes:\n\n\(cur)"),
                                        system: Prompts.memoryConsolidate(lang)).trimmed
        guard !cleaned.isEmpty else { return cur }
        if scope == .global { MemoryStore.setGlobalLearned(cleaned) } else { MemoryStore.setProjectLearned(project.cwd, cleaned) }
        return cleaned
    }

    // MARK: - models

    func loadModels(only: AgentKind? = nil) async {
        for kind in (only.map { [$0] } ?? [.claude, .codex]) {
            let l = lane(of: kind)
            let b = backend(of: kind)
            if settings.connectMethod(for: l) == .app && b == .codex {
                modelOptions[kind] = CodexCLI.cachedModels() // the list `codex -m` accepts
            } else {
                modelOptions[kind] = await LLMEngine.listModels(lane: l, settings: settings)
            }
        }
    }

    // MARK: - utilities

    /// Run blocking file I/O off the main actor so a big project tree can't freeze the UI
    /// mid-turn (snapshot / diff / project context / file writes are all filesystem-bound).
    private func offMain<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await Task.detached(priority: .userInitiated, operation: work).value
    }

    // MARK: - message bookkeeping

    private func setActivity(_ kind: AgentKind, _ text: String) {
        activity[kind] = text
        busy[kind] = !text.isEmpty
    }

    @discardableResult
    private func post(_ role: Role, _ kind: MsgKind, _ text: String, _ pending: Bool,
                      _ id: String?, _ lane: AgentKind, _ agentName: String?) -> String {
        let mid = id ?? "m\(msgSeq)_\(nowMillis())"
        let n: Int
        if let existing = msgN[mid] { n = existing } else { msgSeq += 1; n = msgSeq; msgN[mid] = n }
        let msg = ChatMessage(id: mid, n: n, role: role, kind: kind, text: text, ts: nowMillis(),
                              lane: lane, agentName: agentName, pending: pending)
        if let i = messages.firstIndex(where: { $0.id == mid }) { messages[i] = msg } else { messages.append(msg) }
        Task { await history.recordMessage(msg) }
        return mid
    }
}
