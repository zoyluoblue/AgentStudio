import Foundation

/// Reads live-test credentials from the environment, falling back to the gitignored
/// `tools/test.env` (located relative to this source file). Returns nil when not configured,
/// so provider live tests `XCTSkip` cleanly instead of failing in environments without keys.
enum TestConfig {
    static func value(_ key: String) -> String? {
        if let v = ProcessInfo.processInfo.environment[key], !v.isEmpty { return v }
        return fileValues[key]
    }

    /// Parse `export KEY="VALUE"` / `KEY=VALUE` lines from app/tools/test.env.
    private static let fileValues: [String: String] = {
        // #filePath → .../app/AgentStudioTests/TestConfig.swift  ⇒  app dir is two levels up.
        let appDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let env = appDir.appendingPathComponent("tools/test.env")
        guard let text = try? String(contentsOf: env, encoding: .utf8) else { return [:] }
        var out: [String: String] = [:]
        for raw in text.split(separator: "\n") {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") || line.isEmpty { continue }
            if line.hasPrefix("export ") { line = String(line.dropFirst(7)) }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let k = String(line[line.startIndex..<eq]).trimmingCharacters(in: .whitespaces)
            var v = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if v.hasPrefix("\"") && v.hasSuffix("\"") && v.count >= 2 { v = String(v.dropFirst().dropLast()) }
            out[k] = v
        }
        return out
    }()
}
