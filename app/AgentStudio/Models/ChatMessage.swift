import Foundation

/// One turn in a conversation. Mirrors ChatMessage in ipc.ts.
struct ChatMessage: Codable, Sendable, Identifiable, Hashable {
    var id: String
    /// stable sequence number for referencing turns ("上一句是 #3")
    var n: Int
    var role: Role
    var kind: MsgKind
    var text: String
    /// epoch milliseconds (matches the TS `Date.now()` timestamps)
    var ts: Int
    /// which conversation this belongs to: claude (left) or codex (right)
    var lane: AgentKind
    /// display name of the backend that produced it (e.g. "Claude", "Codex", "DeepSeek")
    var agentName: String?
    /// still being produced (shows a thinking/working state)
    var pending: Bool?
}

/// The open project (a folder on disk). Mirrors ProjectInfo.
struct ProjectInfo: Codable, Sendable, Hashable {
    var cwd: String?
    var name: String?

    static let none = ProjectInfo(cwd: nil, name: nil)
}

/// Per-backend connection status. Mirrors AuthStatus.
struct AuthStatus: Codable, Sendable, Hashable {
    var connected: Bool
    /// e.g. account email or "ChatGPT"
    var detail: String?

    static let disconnected = AuthStatus(connected: false, detail: nil)
}

/// Live phase text per lane ("" = idle): e.g. 规划中 / 执行中 / 审查中 / 思考中 / 重连中.
struct ActivityState: Codable, Sendable, Hashable {
    var claude: String = ""
    var codex: String = ""

    subscript(_ kind: AgentKind) -> String {
        get { kind == .claude ? claude : codex }
        set { if kind == .claude { claude = newValue } else { codex = newValue } }
    }
}

/// Per-lane busy flags. Mirrors BusyState.
struct BusyState: Codable, Sendable, Hashable {
    var claude: Bool = false
    var codex: Bool = false

    subscript(_ kind: AgentKind) -> Bool {
        get { kind == .claude ? claude : codex }
        set { if kind == .claude { claude = newValue } else { codex = newValue } }
    }

    var any: Bool { claude || codex }
}
