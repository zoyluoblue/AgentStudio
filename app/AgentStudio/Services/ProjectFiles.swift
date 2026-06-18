import Foundation

/// Project file utilities for the B1 "whole-file output" agentic strategy:
///  - snapshot / changesSince  → detect what the executor changed, for the reviewer
///  - projectContext           → feed current files to a text-only executor
///  - parseFileBlocks / applyFiles → parse <<<FILE>>> envelopes and write them safely
/// Ported from studio/src/main/diff.ts + deepseekDriver.ts.
enum ProjectFiles {
    typealias Snapshot = [String: String] // relative path -> "mtime:size"

    private static let skip: Set<String> = ["node_modules", "out", "release", "dist", ".next", ".cache", ".git"]
    private static let textExt: Set<String> = [
        "html", "htm", "css", "scss", "sass", "less", "js", "mjs", "cjs", "ts", "tsx", "jsx",
        "json", "md", "txt", "svg", "vue", "xml", "yml", "yaml", "toml", "py", "rb", "go", "rs", "sh",
    ]

    // MARK: - snapshot / diff

    static func snapshot(_ cwd: String) -> Snapshot {
        var acc: Snapshot = [:]
        walk(URL(fileURLWithPath: cwd), base: cwd, acc: &acc, depth: 0)
        return acc
    }

    private static func walk(_ dir: URL, base: String, acc: inout Snapshot, depth: Int) {
        guard depth <= 8 else { return }
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]) else { return }
        for e in entries {
            let name = e.lastPathComponent
            if skip.contains(name) { continue }
            let vals = try? e.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
            if vals?.isDirectory == true {
                if name.hasPrefix(".") { continue }
                walk(e, base: base, acc: &acc, depth: depth + 1)
            } else {
                let size = vals?.fileSize ?? 0
                if size > 2_000_000 { continue }
                let mtime = vals?.contentModificationDate?.timeIntervalSince1970 ?? 0
                acc[rel(e.path, base)] = "\(mtime):\(size)"
            }
        }
    }

    /// Non-ignored, size-capped source files under `cwd`, as relative paths.
    /// Used by SnapshotStore to decide what to checkpoint / restore.
    static func sourceFiles(_ cwd: String) -> [String] {
        var acc: [String] = []
        walkPaths(URL(fileURLWithPath: cwd), prefix: "", acc: &acc, depth: 0)
        return acc
    }

    /// Walk, building each file's relative path from path *components* (never base-stripping), so a
    /// symlinked root (e.g. /var → /private/var resolved by `contentsOfDirectory`) can't break it.
    private static func walkPaths(_ dir: URL, prefix: String, acc: inout [String], depth: Int) {
        guard depth <= 8 else { return }
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey]) else { return }
        for e in entries {
            let name = e.lastPathComponent
            if skip.contains(name) { continue }
            let relPath = prefix.isEmpty ? name : prefix + "/" + name
            let vals = try? e.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            if vals?.isDirectory == true {
                if name.hasPrefix(".") { continue } // skips .agentstudio, .git, etc.
                walkPaths(e, prefix: relPath, acc: &acc, depth: depth + 1)
            } else {
                if (vals?.fileSize ?? 0) > 2_000_000 { continue }
                acc.append(relPath)
            }
        }
    }

    /// Previewable files in the project — HTML pages and images — for the in-pane preview.
    /// Keeps built output (dist/build) and skips junk (via Exporter's walk). HTML sorted first.
    static func previewableFiles(_ cwd: String) -> [String] {
        let exts: Set<String> = ["html", "htm", "png", "jpg", "jpeg", "gif", "svg", "webp"]
        return Exporter.exportableFiles(cwd)
            .filter { exts.contains(($0 as NSString).pathExtension.lowercased()) }
            .sorted { a, b in
                let ah = isHTML(a), bh = isHTML(b)
                if ah != bh { return ah }
                return a.localizedStandardCompare(b) == .orderedAscending
            }
    }

    static func isHTML(_ path: String) -> Bool {
        let e = (path as NSString).pathExtension.lowercased(); return e == "html" || e == "htm"
    }

    /// Review-friendly summary that includes the *content* of new/changed files.
    static func changesSince(_ before: Snapshot, cwd: String) -> String {
        let after = snapshot(cwd)
        var added: [String] = [], modified: [String] = [], deleted: [String] = []
        for (p, sig) in after {
            if before[p] == nil { added.append(p) }
            else if before[p] != sig { modified.append(p) }
        }
        for p in before.keys where after[p] == nil { deleted.append(p) }

        if added.isEmpty && modified.isEmpty && deleted.isEmpty { return "（未检测到文件改动）" }

        var parts = ["改动概览：新增 \(added.count)，修改 \(modified.count)，删除 \(deleted.count)"]
        if !deleted.isEmpty { parts.append("删除：\(deleted.sorted().joined(separator: ", "))") }

        // The reviewer needs the COMPLETE changed file to give a verdict — small caps made it
        // wrongly report "content truncated". Send files in full up to a generous per-file cap,
        // bounded by an overall budget so a big multi-file project still can't blow the context.
        let perFileCap = 60_000
        let totalBudget = 160_000
        var used = 0, shown = 0
        let show = added.sorted().map { ("新增", $0) } + modified.sorted().map { ("修改", $0) }
        for (status, p) in show {
            if used >= totalBudget { break }
            parts.append("\n### \(status): \(p)")
            if let content = try? String(contentsOf: URL(fileURLWithPath: cwd).appendingPathComponent(p), encoding: .utf8) {
                let body = content.count > perFileCap ? String(content.prefix(perFileCap)) + "\n…(文件超大，已截断)" : content
                parts.append("```\n\(body)\n```")
                used += body.count
            } else {
                parts.append("（无法读取内容）")
            }
            shown += 1
        }
        if shown < show.count { parts.append("…还有 \(show.count - shown) 个文件未展示（已超出预览预算）") }
        return parts.joined(separator: "\n")
    }

    // MARK: - project map (compact overview of every file, for awareness without full content)

    /// A one-line-per-file overview (path · line count · first meaningful line) of the whole
    /// project, so the model knows what exists even when full content is budget-trimmed.
    static func projectMap(_ cwd: String, cap: Int = 200) -> String {
        let files = sourceFiles(cwd).sorted()
        guard !files.isEmpty else { return "" }
        let root = URL(fileURLWithPath: cwd)
        var lines: [String] = []
        for rel in files.prefix(cap) {
            let url = root.appendingPathComponent(rel)
            var note = ""
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                let lc = content.split(separator: "\n", omittingEmptySubsequences: false).count
                note = "\(lc) 行"
                if let first = content.split(separator: "\n").first(where: { !String($0).trimmed.isEmpty }) {
                    note += " · " + String(String(first).trimmed.prefix(56))
                }
            } else {
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                note = "\(size) B"
            }
            lines.append("- \(rel)  (\(note))")
        }
        if files.count > cap { lines.append("…还有 \(files.count - cap) 个文件") }
        return lines.joined(separator: "\n")
    }

    // MARK: - project context (for text-only executors)

    static func projectContext(_ cwd: String, budget: Int = 48_000) -> String {
        var files: [(path: String, content: String)] = []
        collectText(URL(fileURLWithPath: cwd), base: cwd, acc: &files, depth: 0)
        var out = ""
        for f in files {
            let body = f.content.count > 30_000 ? String(f.content.prefix(30_000)) + "\n…(已截断)" : f.content
            let chunk = "\n### \(f.path)\n```\n\(body)\n```\n"
            if out.count + chunk.count > budget { out += "\n…(其余文件略)"; break }
            out += chunk
        }
        return out.trimmed
    }

    private static func collectText(_ dir: URL, base: String, acc: inout [(path: String, content: String)], depth: Int) {
        guard depth <= 6, acc.count <= 60 else { return }
        guard let entries = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey]) else { return }
        for e in entries {
            let name = e.lastPathComponent
            if skip.contains(name) || name.hasPrefix(".") { continue }
            let vals = try? e.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            if vals?.isDirectory == true {
                collectText(e, base: base, acc: &acc, depth: depth + 1)
            } else {
                let ext = (name as NSString).pathExtension.lowercased()
                guard textExt.contains(ext), (vals?.fileSize ?? 0) <= 200_000 else { continue }
                if let content = try? String(contentsOf: e, encoding: .utf8) {
                    acc.append((rel(e.path, base), content))
                }
            }
        }
    }

    // MARK: - <<<FILE>>> parse + write

    struct ParsedFile: Sendable { var path: String; var content: String }

    /// Parse `<<<FILE: path>>> … <<<END FILE>>>` blocks; returns the files plus any prose around them.
    static func parseFileBlocks(_ text: String) -> (files: [ParsedFile], prose: String) {
        let pattern = "<<<FILE:\\s*(.+?)\\s*>>>\\r?\\n([\\s\\S]*?)\\r?\\n<<<END FILE>>>"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return ([], text.trimmed) }
        let ns = text as NSString
        let matches = re.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var files: [ParsedFile] = []
        for m in matches where m.numberOfRanges >= 3 {
            let path = ns.substring(with: m.range(at: 1)).trimmed
            var content = ns.substring(with: m.range(at: 2))
            // strip an accidental markdown fence wrapper inside the block
            content = content.replacingOccurrences(of: "^```[\\w-]*\\r?\\n", with: "", options: .regularExpression)
            content = content.replacingOccurrences(of: "\\r?\\n```\\s*$", with: "", options: .regularExpression)
            files.append(ParsedFile(path: path, content: content))
        }
        let prose = re.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: ns.length), withTemplate: "").trimmed
        return (files, prose)
    }

    /// Write parsed files under cwd, refusing any path that escapes the project root.
    @discardableResult
    static func applyFiles(cwd: String, files: [ParsedFile]) -> [String] {
        let root = URL(fileURLWithPath: cwd).standardizedFileURL
        let rootPath = root.path
        var written: [String] = []
        for f in files {
            let relPath = f.path.replacingOccurrences(of: "^[/\\\\]+", with: "", options: .regularExpression)
            let abs = root.appendingPathComponent(relPath).standardizedFileURL
            guard abs.path == rootPath || abs.path.hasPrefix(rootPath + "/") else {
                Log.shared.event("files.write.skip", ["path": f.path, "reason": "escapes root"])
                continue
            }
            do {
                try FileManager.default.createDirectory(at: abs.deletingLastPathComponent(), withIntermediateDirectories: true)
                try f.content.write(to: abs, atomically: true, encoding: .utf8)
                written.append(relPath)
            } catch {
                Log.shared.event("files.write.error", ["path": relPath, "err": "\(error)"])
            }
        }
        return written
    }

    // MARK: - <<<EDIT>>> search/replace (B2 incremental edits)

    struct Edit: Sendable { var path: String; var search: String; var replace: String }

    /// Parse `<<<EDIT: path>>> <<<SEARCH>>> … <<<REPLACE>>> … <<<END EDIT>>>` blocks.
    static func parseEdits(_ text: String) -> [Edit] {
        let pattern = "<<<EDIT:\\s*(.+?)\\s*>>>\\r?\\n<<<SEARCH>>>\\r?\\n([\\s\\S]*?)\\r?\\n<<<REPLACE>>>\\r?\\n([\\s\\S]*?)\\r?\\n<<<END EDIT>>>"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        var edits: [Edit] = []
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) where m.numberOfRanges >= 4 {
            edits.append(Edit(path: ns.substring(with: m.range(at: 1)).trimmed,
                              search: ns.substring(with: m.range(at: 2)),
                              replace: ns.substring(with: m.range(at: 3))))
        }
        return edits
    }

    /// Apply edits by finding `search` verbatim (newline-normalized) and replacing the first match.
    /// Returns which files were changed and which edits didn't match (so callers can fall back).
    @discardableResult
    static func applyEdits(cwd: String, edits: [Edit]) -> (applied: [String], failed: [String]) {
        let root = URL(fileURLWithPath: cwd).standardizedFileURL
        let rootPath = root.path
        var applied: [String] = [], failed: [String] = []
        func norm(_ s: String) -> String { s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n") }
        for e in edits {
            let relPath = e.path.replacingOccurrences(of: "^[/\\\\]+", with: "", options: .regularExpression)
            let abs = root.appendingPathComponent(relPath).standardizedFileURL
            guard abs.path == rootPath || abs.path.hasPrefix(rootPath + "/"),
                  var content = try? String(contentsOf: abs, encoding: .utf8) else {
                Log.shared.event("files.edit.skip", ["path": e.path]); failed.append(relPath); continue
            }
            content = norm(content)
            let search = norm(e.search)
            // Exact match first; then fall back to a trimmed snippet. Models very often pad the SEARCH
            // text with a leading/trailing newline (assuming files end in one) or stray indentation —
            // an exact compare then silently misses. Trimming recovers the common case safely, since
            // the fallback only runs when the exact match already failed.
            var matched = search.isEmpty ? nil : content.range(of: search)
            if matched == nil {
                let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { matched = content.range(of: trimmed) }
            }
            guard let r = matched else { failed.append(relPath); continue }
            content.replaceSubrange(r, with: norm(e.replace))
            do { try content.write(to: abs, atomically: true, encoding: .utf8); applied.append(relPath) }
            catch { Log.shared.event("files.edit.error", ["path": relPath, "err": "\(error)"]); failed.append(relPath) }
        }
        return (applied, failed)
    }

    /// Parse a write turn that may contain both whole-file (`<<<FILE>>>`) and edit (`<<<EDIT>>>`)
    /// blocks; returns both plus the surrounding prose (with both kinds of blocks stripped).
    static func parseChanges(_ text: String) -> (files: [ParsedFile], edits: [Edit], prose: String) {
        let (files, prose1) = parseFileBlocks(text)
        let edits = parseEdits(text)
        var prose = prose1
        if let re = try? NSRegularExpression(pattern: "<<<EDIT:[\\s\\S]*?<<<END EDIT>>>") {
            prose = re.stringByReplacingMatches(in: prose1, range: NSRange(prose1.startIndex..., in: prose1), withTemplate: "").trimmed
        }
        return (files, edits, prose)
    }

    private static func rel(_ path: String, _ base: String) -> String {
        var b = base
        if !b.hasSuffix("/") { b += "/" }
        if path.hasPrefix(b) { return String(path.dropFirst(b.count)) }
        // `contentsOfDirectory` resolves symlinked roots (e.g. /var → /private/var) while `base`
        // may not be resolved; retry against the resolved base so the relative path is correct.
        let rb = URL(fileURLWithPath: base).resolvingSymlinksInPath().path + "/"
        return path.hasPrefix(rb) ? String(path.dropFirst(rb.count)) : path
    }
}
