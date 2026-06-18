import Foundation

/// Resolves the app's on-disk locations, mirroring the Electron app's `userData` layout:
///   ~/Library/Application Support/AgentStudio/
///     settings.json
///     history/<id>.json
///     memory/global.md, global.auto.md, projects/
///     logs/agentstudio.log
enum AppPaths {
    /// Root data directory (created on first access).
    static let root: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("AgentStudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static var settingsFile: URL { root.appendingPathComponent("settings.json") }

    static var usageFile: URL { root.appendingPathComponent("usage.json") }

    static var historyDir: URL {
        let d = root.appendingPathComponent("history", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static var memoryDir: URL {
        let d = root.appendingPathComponent("memory", isDirectory: true)
        try? FileManager.default.createDirectory(at: d.appendingPathComponent("projects"), withIntermediateDirectories: true)
        return d
    }

    static var logFile: URL {
        let d = root.appendingPathComponent("logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("agentstudio.log")
    }
}

/// epoch milliseconds, matching the TS `Date.now()` timestamps used across the data model.
func nowMillis() -> Int { Int(Date().timeIntervalSince1970 * 1000) }
