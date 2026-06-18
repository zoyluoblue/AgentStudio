import Foundation

/// Provider-neutral chat message (system handled separately for Anthropic).
enum LLMRole: String, Codable, Sendable { case system, user, assistant }

struct LLMMessage: Codable, Sendable, Hashable {
    var role: LLMRole
    var content: String
}

/// A high-level completion request, before key/proxy/model are resolved from settings.
struct ChatRequest: Sendable {
    var backend: Backend
    var lane: Lane
    /// "" / nil → the provider's default model.
    var model: String?
    var systemPrompt: String?
    var messages: [LLMMessage]
    var maxTokens: Int = 16_000
}

/// What a provider client actually needs once settings are resolved.
struct ResolvedRequest: @unchecked Sendable {
    var model: String
    var systemPrompt: String?
    var messages: [LLMMessage]
    var maxTokens: Int
    var apiKey: String
    /// API base URL (default or user override); the client appends the standard path.
    var baseURL: String
    /// Proxy-configured session (URLSession is thread-safe).
    var session: URLSession
}

/// Streaming output: incremental assistant text, optional phase/status text, and a final
/// token-usage report (for cost metering) when the provider includes one.
enum StreamEvent: Sendable {
    case delta(String)
    case status(String)
    case usage(input: Int, output: Int)
}

enum ProviderError: LocalizedError {
    case missingKey(Backend)
    case http(status: Int, body: String)
    case transient(String)
    case cancelled
    case empty
    case other(String)

    var errorDescription: String? {
        switch self {
        case .missingKey(let b): return "请先在设置里填写 \(b.displayName) 的 API Key。"
        case .http(let status, let body):
            let snippet = body.isEmpty ? "" : "：\(String(body.prefix(300)))"
            return "请求失败（HTTP \(status)）\(snippet)"
        case .transient(let m): return "网络连接被中断：\(m)"
        case .cancelled: return "已停止"
        case .empty: return "模型返回为空"
        case .other(let m): return m
        }
    }
}

/// A provider client streams a resolved request, yielding text deltas.
protocol ProviderClient: Sendable {
    func stream(_ req: ResolvedRequest) -> AsyncThrowingStream<StreamEvent, Error>
}

// MARK: - Model catalogs & defaults

enum LLMModels {
    /// Default model per backend when the user hasn't picked one.
    static func defaultModel(_ backend: Backend) -> String {
        switch backend {
        case .claude: return "claude-opus-4-8"
        case .codex: return "gpt-4o" // placeholder — user picks from the live model list in key mode
        case .deepseek: return "deepseek-v4-pro"
        }
    }

    /// Cheap model for one-shot work (memory extraction / consolidation).
    static func cheapModel(_ backend: Backend) -> String {
        switch backend {
        case .claude: return "claude-haiku-4-5"
        case .codex: return "gpt-4o-mini"
        case .deepseek: return "deepseek-v4-flash"
        }
    }

    /// Curated Claude models the HTTP API accepts as-is (no date suffix).
    static let claude: [ModelOption] = [
        ModelOption(id: "claude-opus-4-8", label: "Opus 4.8"),
        ModelOption(id: "claude-opus-4-7", label: "Opus 4.7"),
        ModelOption(id: "claude-opus-4-6", label: "Opus 4.6"),
        ModelOption(id: "claude-sonnet-4-6", label: "Sonnet 4.6"),
        ModelOption(id: "claude-haiku-4-5", label: "Haiku 4.5"),
    ]

    static let deepseekFallback: [ModelOption] = [
        ModelOption(id: "deepseek-v4-flash", label: "DeepSeek V4 Flash"),
        ModelOption(id: "deepseek-v4-pro", label: "DeepSeek V4 Pro"),
    ]
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
