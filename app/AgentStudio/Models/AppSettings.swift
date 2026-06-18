import Foundation

/// User preferences, persisted to Application Support/AgentStudio/settings.json.
/// Mirrors AppSettings in ipc.ts.
///
/// NOTE: `apiKeys` is persisted here for Phase 1 convenience. Phase 2 moves the key
/// material into the macOS Keychain (see KeychainStore) and keeps only non-secret
/// preferences in this JSON file.
struct AppSettings: Codable, Sendable, Hashable {
    /// system = inherit env proxy; custom = use proxyUrl; none = no proxy
    var proxyMode: ProxyMode
    /// e.g. http://127.0.0.1:7890 — used when proxyMode == .custom
    var proxyUrl: String
    /// master = left only, slave = right only, both = all
    var proxyScope: ProxyScope
    var theme: ThemeMode
    /// LLM running in the left (master/planner) lane
    var masterBackend: Backend
    /// LLM running in the right (slave/executor) lane
    var slaveBackend: Backend
    /// Per-lane auth method. DeepSeek is always .key (no CLI login).
    var connectMethod: PerLane<ConnectMethod>
    /// Per-lane API key (left/right connect independently, even with the same model).
    var apiKeys: PerLane<String>
    /// Per-lane custom API base URL (used only in key mode when `useDefaultBaseURL` is false).
    var baseURLs: PerLane<String>
    /// Per-lane: use our built-in default base URL (true) instead of `baseURLs` (false).
    var useDefaultBaseURL: PerLane<Bool>
    /// Auto-extract learned memory from finished conversations.
    var autoMemory: Bool
    /// UI language.
    var language: Lang
    /// Monthly spend cap in USD for BYO-key API usage (0 = no budget). New turns are blocked once
    /// this month's estimated spend reaches the cap.
    var monthlyBudgetUSD: Double
    /// v2.0 — MCP servers the app-mode CLI agents (Claude Code / Codex) can call as tools.
    var mcpServers: [MCPServer]
    /// A-line — let the executor RUN commands (install deps, tests, git, dev servers), not just
    /// edit files. Powerful; off by default. Affects the Claude executor (Bash tool) and the
    /// key-mode agent loop's run_command tool.
    var allowCommands: Bool
    /// Plan B — for the Anthropic **key** lane, drive the official Claude Agent SDK (Node sidecar)
    /// when available, instead of the built-in AgentEngine. Falls back automatically if node / the
    /// bridge isn't present. OpenAI/DeepSeek key lanes always use AgentEngine.
    var useAgentSDK: Bool

    static let defaults = AppSettings(
        proxyMode: .system,
        proxyUrl: "",
        proxyScope: .both,
        theme: .system,
        masterBackend: .claude,
        slaveBackend: .codex,
        // app = reuse the local Claude Code / Codex CLI login (no API key). Defaults: left=Claude, right=Codex.
        connectMethod: PerLane(master: .app, slave: .app),
        apiKeys: PerLane(""),
        baseURLs: PerLane(
            master: AppSettings.defaultBaseURL(.claude),
            slave: AppSettings.defaultBaseURL(.codex)
        ),
        useDefaultBaseURL: PerLane(true),
        autoMemory: true,
        language: .zh,
        monthlyBudgetUSD: 0,
        mcpServers: [],
        allowCommands: false,
        useAgentSDK: true
    )

    /// Built-in default API base URL per backend (the client appends the standard path).
    static func defaultBaseURL(_ b: Backend) -> String {
        switch b {
        case .claude: return "https://api.anthropic.com"
        case .codex: return "https://api.openai.com/v1"
        case .deepseek: return "https://api.deepseek.com"
        }
    }

    /// The base URL a lane will actually use: the default for its backend, or the user's override.
    func effectiveBaseURL(for lane: Lane) -> String {
        let b = backend(for: lane)
        let raw = useDefaultBaseURL[lane] ? AppSettings.defaultBaseURL(b) : baseURLs[lane].trimmingCharacters(in: .whitespacesAndNewlines)
        let v = raw.isEmpty ? AppSettings.defaultBaseURL(b) : raw
        return v.hasSuffix("/") ? String(v.dropLast()) : v
    }

    /// The lane → backend mapping.
    func backend(for lane: Lane) -> Backend {
        lane == .master ? masterBackend : slaveBackend
    }

    /// How a lane authenticates. DeepSeek has no CLI login, so a DeepSeek lane is always .key.
    func connectMethod(for lane: Lane) -> ConnectMethod {
        backend(for: lane) == .deepseek ? .key : connectMethod[lane]
    }

    /// The API key configured for a lane ("" if none).
    func apiKey(for lane: Lane) -> String {
        apiKeys[lane].trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Codable (apiKeys excluded — persisted to the Keychain, not settings.json)

extension AppSettings {
    private enum CodingKeys: String, CodingKey {
        case proxyMode, proxyUrl, proxyScope, theme, masterBackend, slaveBackend, connectMethod
        case baseURLs, useDefaultBaseURL, autoMemory, language, monthlyBudgetUSD, mcpServers, allowCommands, useAgentSDK
        // `apiKeys` is intentionally omitted; SettingsStore overlays it from KeychainStore.
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings.defaults
        proxyMode = try c.decodeIfPresent(ProxyMode.self, forKey: .proxyMode) ?? d.proxyMode
        proxyUrl = try c.decodeIfPresent(String.self, forKey: .proxyUrl) ?? d.proxyUrl
        proxyScope = try c.decodeIfPresent(ProxyScope.self, forKey: .proxyScope) ?? d.proxyScope
        theme = try c.decodeIfPresent(ThemeMode.self, forKey: .theme) ?? d.theme
        masterBackend = try c.decodeIfPresent(Backend.self, forKey: .masterBackend) ?? d.masterBackend
        slaveBackend = try c.decodeIfPresent(Backend.self, forKey: .slaveBackend) ?? d.slaveBackend
        connectMethod = try c.decodeIfPresent(PerLane<ConnectMethod>.self, forKey: .connectMethod) ?? d.connectMethod
        baseURLs = try c.decodeIfPresent(PerLane<String>.self, forKey: .baseURLs) ?? d.baseURLs
        useDefaultBaseURL = try c.decodeIfPresent(PerLane<Bool>.self, forKey: .useDefaultBaseURL) ?? d.useDefaultBaseURL
        autoMemory = try c.decodeIfPresent(Bool.self, forKey: .autoMemory) ?? d.autoMemory
        language = try c.decodeIfPresent(Lang.self, forKey: .language) ?? d.language
        monthlyBudgetUSD = try c.decodeIfPresent(Double.self, forKey: .monthlyBudgetUSD) ?? d.monthlyBudgetUSD
        mcpServers = try c.decodeIfPresent([MCPServer].self, forKey: .mcpServers) ?? d.mcpServers
        allowCommands = try c.decodeIfPresent(Bool.self, forKey: .allowCommands) ?? d.allowCommands
        useAgentSDK = try c.decodeIfPresent(Bool.self, forKey: .useAgentSDK) ?? d.useAgentSDK
        apiKeys = PerLane("") // overlaid from Keychain after decode
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(proxyMode, forKey: .proxyMode)
        try c.encode(proxyUrl, forKey: .proxyUrl)
        try c.encode(proxyScope, forKey: .proxyScope)
        try c.encode(theme, forKey: .theme)
        try c.encode(masterBackend, forKey: .masterBackend)
        try c.encode(slaveBackend, forKey: .slaveBackend)
        try c.encode(connectMethod, forKey: .connectMethod)
        try c.encode(baseURLs, forKey: .baseURLs)
        try c.encode(useDefaultBaseURL, forKey: .useDefaultBaseURL)
        try c.encode(autoMemory, forKey: .autoMemory)
        try c.encode(language, forKey: .language)
        try c.encode(monthlyBudgetUSD, forKey: .monthlyBudgetUSD)
        try c.encode(mcpServers, forKey: .mcpServers)
        try c.encode(allowCommands, forKey: .allowCommands)
        try c.encode(useAgentSDK, forKey: .useAgentSDK)
    }
}
