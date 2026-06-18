import Foundation

/// Saved-conversation metadata used for history lists and search rows. Mirrors SessionMeta.
struct SessionMeta: Codable, Sendable, Identifiable, Hashable {
    var id: String
    var projectCwd: String
    var projectName: String
    var mode: Mode
    /// auto-derived from the first user message, user-editable
    var title: String
    var createdAt: Int
    var updatedAt: Int
    var messageCount: Int
}

/// A full saved conversation: metadata + transcript.
///
/// Unlike the Electron version, the native app talks to provider APIs directly and
/// keeps the message array as the single source of conversational context — so there
/// are no `claude --resume` / codex thread ids to persist.
struct Session: Codable, Sendable, Identifiable, Hashable {
    var id: String
    var projectCwd: String
    var projectName: String
    var mode: Mode
    var title: String
    var createdAt: Int
    var updatedAt: Int
    var messageCount: Int
    var messages: [ChatMessage]

    var meta: SessionMeta {
        SessionMeta(
            id: id,
            projectCwd: projectCwd,
            projectName: projectName,
            mode: mode,
            title: title.isEmpty ? "（未命名对话）" : title,
            createdAt: createdAt,
            updatedAt: updatedAt,
            messageCount: messages.count
        )
    }
}

/// One search match inside a saved session. Mirrors SearchHit.
struct SearchHit: Codable, Sendable, Identifiable, Hashable {
    var sessionId: String
    var sessionTitle: String
    var projectName: String
    var messageId: String
    var n: Int
    var role: Role
    var lane: AgentKind
    var ts: Int
    /// text around the match, trimmed for display
    var snippet: String

    var id: String { "\(sessionId)#\(messageId)" }
}

/// Payload delivered when a saved session is resumed into the live chat. Mirrors SessionLoad.
struct SessionLoad: Sendable {
    var project: ProjectInfo
    var mode: Mode
    var messages: [ChatMessage]
    /// message to scroll to + briefly highlight (e.g. a search hit)
    var focusMessageId: String?
}
