import Foundation

/// Long-term memory: plain Markdown files that every backend reads.
/// A global file applies everywhere; each project gets its own file living INSIDE the
/// project (`<project>/.agentstudio/memory.md`) so it travels with the project and can be
/// inspected / version-controlled. Curated memory is user-written; learned memory is
/// auto-extracted from finished conversations (kept separate).
///
/// Stateless: every method is a pure function of the filesystem, so it is safe to call
/// from any actor. Mirrors studio/src/main/memory.ts.
enum MemoryStore {
    /// Soft cap on the injected memory block so it can't blow up the context window.
    private static let maxChars = 12_000

    // ---- file locations ----
    private static var globalCurated: URL { AppPaths.memoryDir.appendingPathComponent("global.md") }
    private static var globalLearned: URL { AppPaths.memoryDir.appendingPathComponent("global.auto.md") }
    private static func projectCurated(_ cwd: String) -> URL {
        URL(fileURLWithPath: cwd).appendingPathComponent(".agentstudio/memory.md")
    }
    private static func projectLearned(_ cwd: String) -> URL {
        URL(fileURLWithPath: cwd).appendingPathComponent(".agentstudio/memory.auto.md")
    }

    // ---- low-level io ----
    private static func read(_ url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
    private static func write(_ url: URL, _ content: String) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            Log.shared.event("memory.write.error", ["err": "\(error)"])
        }
    }

    // ---- curated ----
    static func getGlobal() -> String { read(globalCurated) }
    static func getProject(_ cwd: String?) -> String { cwd.map { read(projectCurated($0)) } ?? "" }
    static func setGlobal(_ content: String) {
        write(globalCurated, content)
        Log.shared.event("memory.set", ["scope": "global", "len": content.count])
    }
    static func setProject(_ cwd: String?, _ content: String) {
        guard let cwd else { return }
        write(projectCurated(cwd), content)
        Log.shared.event("memory.set", ["scope": "project", "len": content.count])
    }

    /// Append one fact as a bullet — to the project memory if a project is open, else global.
    static func appendCurated(_ cwd: String?, _ line: String) {
        let fact = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fact.isEmpty else { return }
        let url = cwd.map(projectCurated) ?? globalCurated
        let cur = read(url).trimmedTrailing
        write(url, "\(cur.isEmpty ? "" : cur + "\n")- \(fact)\n")
        Log.shared.event("memory.append", ["scope": cwd != nil ? "project" : "global", "len": fact.count])
    }

    // ---- learned ----
    static func getGlobalLearned() -> String { read(globalLearned) }
    static func getProjectLearned(_ cwd: String?) -> String { cwd.map { read(projectLearned($0)) } ?? "" }
    static func setGlobalLearned(_ content: String) {
        write(globalLearned, content)
        Log.shared.event("memory.learned.set", ["scope": "global", "len": content.count])
    }
    static func setProjectLearned(_ cwd: String?, _ content: String) {
        guard let cwd else { return }
        write(projectLearned(cwd), content)
        Log.shared.event("memory.learned.set", ["scope": "project", "len": content.count])
    }

    /// Append auto-extracted bullets to learned memory (project if open, else global).
    static func appendLearned(_ cwd: String?, _ lines: [String]) {
        let items = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !items.isEmpty else { return }
        let url = cwd.map(projectLearned) ?? globalLearned
        let cur = read(url).trimmedTrailing
        let add = items.map { "- \($0)" }.joined(separator: "\n")
        write(url, "\(cur.isEmpty ? "" : cur + "\n")\(add)\n")
        Log.shared.event("memory.learned.append", ["scope": cwd != nil ? "project" : "global", "n": items.count])
    }

    // ---- read by scope/kind (used by the IPC-equivalent UI calls) ----
    static func get(scope: MemoryScope, kind: MemoryKind, cwd: String?) -> String {
        switch (scope, kind) {
        case (.global, .curated): return getGlobal()
        case (.global, .learned): return getGlobalLearned()
        case (.project, .curated): return getProject(cwd)
        case (.project, .learned): return getProjectLearned(cwd)
        }
    }
    static func set(scope: MemoryScope, kind: MemoryKind, content: String, cwd: String?) {
        switch (scope, kind) {
        case (.global, .curated): setGlobal(content)
        case (.global, .learned): setGlobalLearned(content)
        case (.project, .curated): setProject(cwd, content)
        case (.project, .learned): setProjectLearned(cwd, content)
        }
    }

    /// Combined memory block injected into prompts ("" when there is no memory).
    /// Curated first, learned after.
    static func context(_ cwd: String?) -> String {
        var sections: [String] = []
        let gc = getGlobal().trimmed
        let pc = getProject(cwd).trimmed
        let gl = getGlobalLearned().trimmed
        let pl = getProjectLearned(cwd).trimmed
        if !gc.isEmpty { sections.append("【全局记忆】\n\(gc)") }
        if !pc.isEmpty { sections.append("【项目记忆】\n\(pc)") }
        if !gl.isEmpty { sections.append("【全局·自动记忆】\n\(gl)") }
        if !pl.isEmpty { sections.append("【项目·自动记忆】\n\(pl)") }
        guard !sections.isEmpty else { return "" }
        var body = sections.joined(separator: "\n\n")
        if body.count > maxChars { body = String(body.prefix(maxChars)) + "\n…（记忆过长，已截断）" }
        return "以下是用户的长期记忆，请在本次回答中参考并遵循：\n\(body)"
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    /// Trailing-only trim, matching JS `trimEnd()`.
    var trimmedTrailing: String {
        var s = self
        while let last = s.last, last.isWhitespace { s.removeLast() }
        return s
    }
}
