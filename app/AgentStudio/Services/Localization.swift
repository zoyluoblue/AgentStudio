import SwiftUI

/// UI language. Persisted in settings; toggled from the top bar.
enum Lang: String, Codable, Sendable, Hashable, CaseIterable {
    case zh, en
    var toggled: Lang { self == .zh ? .en : .zh }
    /// Label for the toggle button (shows the language you'd switch TO).
    var switchLabel: String { self == .zh ? "EN" : "中" }
    /// Pick the string for the current language.
    func t(_ zh: String, _ en: String) -> String { self == .en ? en : zh }
}

/// SwiftUI environment value so any view can localize without threading the language through.
private struct LangKey: EnvironmentKey { static let defaultValue: Lang = .zh }
extension EnvironmentValues {
    var lang: Lang {
        get { self[LangKey.self] }
        set { self[LangKey.self] = newValue }
    }
}

/// A lane's single backend+method choice (replaces the separate backend / method pickers).
/// Each option fixes both which provider runs and how it connects.
enum LaneOption: String, CaseIterable, Hashable, Sendable, Identifiable {
    case claudeApi, openAI, deepseek, claudeCode, codex

    var id: String { rawValue }

    var backend: Backend {
        switch self {
        case .claudeApi, .claudeCode: return .claude
        case .openAI, .codex: return .codex
        case .deepseek: return .deepseek
        }
    }

    var method: ConnectMethod {
        switch self {
        case .claudeApi, .openAI, .deepseek: return .key
        case .claudeCode, .codex: return .app
        }
    }

    /// Product names — not translated.
    var label: String {
        switch self {
        case .claudeApi: return "Claude API"
        case .openAI: return "OpenAI"
        case .deepseek: return "DeepSeek"
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        }
    }

    static func from(backend: Backend, method: ConnectMethod) -> LaneOption {
        switch (backend, method) {
        case (.claude, .app): return .claudeCode
        case (.claude, _): return .claudeApi
        case (.codex, .app): return .codex
        case (.codex, _): return .openAI
        case (.deepseek, _): return .deepseek
        }
    }
}
