import Foundation

/// v2.0 — MCP / plugin support. A user-registered MCP server the spawned CLI agent (Claude Code /
/// Codex, app mode) can call as tools. We wire these into the CLI invocation; the HTTP/key path
/// doesn't run an MCP loop yet, so MCP applies in app mode.
struct MCPServer: Codable, Sendable, Hashable, Identifiable {
    var id: String          // server name (unique, used as the tool namespace mcp__<id>__*)
    var command: String     // e.g. "npx"
    var args: [String]      // e.g. ["-y", "@modelcontextprotocol/server-filesystem", "/path"]
    var enabled: Bool = true
}

/// A one-click MCP server preset — the common plugins a non-coder would want, pre-filled so they
/// don't have to know package names. (B — MCP presets: filesystem / fetch / browser.)
struct MCPPreset: Identifiable, Sendable {
    let id: String              // becomes the server id / tool namespace
    let zhTitle: String, enTitle: String
    let zhDesc: String, enDesc: String
    let command: String
    let baseArgs: [String]
    let appendProjectDir: Bool  // filesystem needs a folder to operate on
    let zhNote: String?, enNote: String?   // a prerequisite hint, if any

    /// Concrete args, filling in the project directory for servers that need one.
    func args(projectDir: String?) -> [String] {
        appendProjectDir ? baseArgs + [projectDir ?? NSHomeDirectory()] : baseArgs
    }
    func server(projectDir: String?) -> MCPServer {
        MCPServer(id: id, command: command, args: args(projectDir: projectDir), enabled: true)
    }
}

enum MCPConfig {
    /// The built-in presets shown as one-click chips in Settings.
    static let presets: [MCPPreset] = [
        MCPPreset(id: "filesystem", zhTitle: "文件系统", enTitle: "Filesystem",
                  zhDesc: "让 AI 直接读写当前项目文件夹里的文件", enDesc: "Let the AI read/write files in the current project folder",
                  command: "npx", baseArgs: ["-y", "@modelcontextprotocol/server-filesystem"],
                  appendProjectDir: true, zhNote: nil, enNote: nil),
        MCPPreset(id: "fetch", zhTitle: "网页抓取", enTitle: "Web fetch",
                  zhDesc: "让 AI 抓取并阅读网页内容", enDesc: "Let the AI fetch and read web pages",
                  command: "uvx", baseArgs: ["mcp-server-fetch"],
                  appendProjectDir: false, zhNote: "需本机装有 Python(uvx)", enNote: "Requires Python (uvx) on this Mac"),
        MCPPreset(id: "browser", zhTitle: "浏览器", enTitle: "Browser",
                  zhDesc: "让 AI 打开网页、点击、截图", enDesc: "Let the AI open pages, click, and screenshot",
                  command: "npx", baseArgs: ["-y", "@modelcontextprotocol/server-puppeteer"],
                  appendProjectDir: false, zhNote: "首次会下载浏览器内核", enNote: "Downloads a browser engine on first run"),
    ]

    /// Runnable, enabled servers.
    static func enabled(_ settings: AppSettings) -> [MCPServer] {
        settings.mcpServers.filter { $0.enabled && !$0.command.trimmed.isEmpty && !$0.id.trimmed.isEmpty }
    }

    /// Write a Claude-CLI `--mcp-config` JSON for the given servers; returns its temp path, or nil.
    static func claudeConfigFile(_ servers: [MCPServer]) -> String? {
        guard !servers.isEmpty else { return nil }
        var entries: [String: Any] = [:]
        for s in servers { entries[s.id] = ["command": s.command, "args": s.args] }
        guard let data = try? JSONSerialization.data(withJSONObject: ["mcpServers": entries]) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("as-mcp-\(UUID().uuidString).json")
        return (try? data.write(to: url)) != nil ? url.path : nil
    }

    /// Tool-allow patterns for the Claude CLI write turn (`mcp__<name>` allows that server's tools).
    static func claudeAllowTools(_ servers: [MCPServer]) -> [String] { servers.map { "mcp__\($0.id)" } }

    /// Codex `-c` config args registering the servers under `[mcp_servers.<name>]`.
    static func codexConfigArgs(_ servers: [MCPServer]) -> [String] {
        var out: [String] = []
        for s in servers {
            out += ["-c", "mcp_servers.\(s.id).command=\"\(s.command)\""]
            if !s.args.isEmpty {
                let arr = s.args.map { "\"\($0)\"" }.joined(separator: ",")
                out += ["-c", "mcp_servers.\(s.id).args=[\(arr)]"]
            }
        }
        return out
    }
}
