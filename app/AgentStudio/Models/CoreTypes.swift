import Foundation

// Swift port of the shared enums in studio/src/shared/ipc.ts.
// These are the vocabulary every layer (stores, providers, orchestrator, UI) speaks.

enum Role: String, Codable, Sendable, Hashable {
    case user, claude, codex, system
}

enum MsgKind: String, Codable, Sendable, Hashable {
    case text, plan, diff, review, progress, error
}

/// Left lane (master/planner) is keyed "claude", right lane (slave/executor) is keyed "codex".
enum AgentKind: String, Codable, Sendable, Hashable, CaseIterable {
    case claude, codex
}

/// The two lane roles, surfaced to the user and used for proxy scoping.
enum Lane: String, Codable, Sendable, Hashable {
    case master, slave
}

/// Which LLM actually runs in a lane. DeepSeek is master-only (text planning, no file writes).
enum Backend: String, Codable, Sendable, Hashable, CaseIterable {
    case claude, codex, deepseek

    /// Friendly display name (e.g. "Claude", "Codex", "DeepSeek").
    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .deepseek: return "DeepSeek"
        }
    }
}

enum Mode: String, Codable, Sendable, Hashable {
    case solo, collab
}

enum ProxyMode: String, Codable, Sendable, Hashable {
    case system, custom, none
}

/// Which lanes the proxy applies to.
enum ProxyScope: String, Codable, Sendable, Hashable {
    case master, slave, both
}

enum ThemeMode: String, Codable, Sendable, Hashable {
    case system, light, dark
}

/// How a backend authenticates: app = CLI/OAuth login, key = API key.
/// (Native app is key-mode for every backend, but the type is kept for parity.)
enum ConnectMethod: String, Codable, Sendable, Hashable {
    case app, key
}

/// Long-term memory scope: global (all projects) or the current project only.
enum MemoryScope: String, Codable, Sendable, Hashable {
    case global, project
}

/// Memory kind: curated (user-written / explicit "记住") or learned (auto-extracted from chats).
enum MemoryKind: String, Codable, Sendable, Hashable {
    case curated, learned
}

/// A selectable model: `id` is passed to the API; `label` is the friendly display name.
struct ModelOption: Codable, Sendable, Hashable, Identifiable {
    var id: String
    var label: String
}

/// Keyed-by-backend container that encodes as `{ "claude": ..., "codex": ..., "deepseek": ... }`,
/// matching the `Record<Backend, T>` shape used by the TS settings file.
struct PerBackend<Value: Codable & Sendable & Hashable>: Codable, Sendable, Hashable {
    var claude: Value
    var codex: Value
    var deepseek: Value

    init(claude: Value, codex: Value, deepseek: Value) {
        self.claude = claude
        self.codex = codex
        self.deepseek = deepseek
    }

    init(_ uniform: Value) {
        self.claude = uniform
        self.codex = uniform
        self.deepseek = uniform
    }

    subscript(_ backend: Backend) -> Value {
        get {
            switch backend {
            case .claude: return claude
            case .codex: return codex
            case .deepseek: return deepseek
            }
        }
        set {
            switch backend {
            case .claude: claude = newValue
            case .codex: codex = newValue
            case .deepseek: deepseek = newValue
            }
        }
    }
}

/// Keyed-by-lane container (left = master, right = slave). Connection config (key / base URL /
/// method) is per-lane so the two lanes connect independently — even when they use the same model.
struct PerLane<Value: Codable & Sendable & Hashable>: Codable, Sendable, Hashable {
    var master: Value
    var slave: Value

    init(master: Value, slave: Value) {
        self.master = master
        self.slave = slave
    }

    init(_ uniform: Value) {
        self.master = uniform
        self.slave = uniform
    }

    subscript(_ lane: Lane) -> Value {
        get { lane == .master ? master : slave }
        set { if lane == .master { master = newValue } else { slave = newValue } }
    }
}
