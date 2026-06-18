import Foundation

/// R6 — share / export. Packages the project into a clean ZIP (no node_modules, git, caches, or
/// AgentStudio's own snapshot folder) using `NSFileCoordinator(.forUploading)` — no external deps.
/// Built output (dist/build/out) is kept, since that's part of the result worth sharing.
enum Exporter {
    /// Heavy/internal directories never worth exporting.
    private static let skipDirs: Set<String> = ["node_modules", ".git", ".agentstudio", ".cache", ".next"]
    private static let maxFile = 25_000_000 // 25 MB per file

    /// Relative paths to include in an export (keeps dist/build; drops junk and dot-dirs).
    static func exportableFiles(_ cwd: String) -> [String] {
        var acc: [String] = []
        walk(URL(fileURLWithPath: cwd), base: cwd, acc: &acc, depth: 0)
        return acc
    }

    private static func walk(_ dir: URL, base: String, acc: inout [String], depth: Int) {
        guard depth <= 10 else { return }
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey]) else { return }
        for e in entries {
            let name = e.lastPathComponent
            if skipDirs.contains(name) { continue }
            let vals = try? e.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            if vals?.isDirectory == true {
                if name.hasPrefix(".") { continue }
                walk(e, base: base, acc: &acc, depth: depth + 1)
            } else {
                if name.hasPrefix(".") && name != ".gitignore" { continue }
                if (vals?.fileSize ?? 0) > maxFile { continue }
                acc.append(rel(e.path, base))
            }
        }
    }

    /// Stage the filtered files under a temp `<name>/` folder and zip it. Returns the temp zip URL
    /// (caller moves it to its final destination), or nil on failure. Off-main work.
    static func makeZip(cwd: String, name: String) -> URL? {
        let fm = FileManager.default
        let safe = sanitize(name)
        let stagingRoot = fm.temporaryDirectory.appendingPathComponent("AgentStudioExport-\(UUID().uuidString)", isDirectory: true)
        let projectDir = stagingRoot.appendingPathComponent(safe, isDirectory: true)
        let src = URL(fileURLWithPath: cwd)
        do {
            try fm.createDirectory(at: projectDir, withIntermediateDirectories: true)
            for relPath in exportableFiles(cwd) {
                let from = src.appendingPathComponent(relPath)
                let to = projectDir.appendingPathComponent(relPath)
                try? fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? fm.copyItem(at: from, to: to)
            }
        } catch {
            try? fm.removeItem(at: stagingRoot)
            return nil
        }

        let zipURL = stagingRoot.appendingPathComponent("\(safe).zip")
        var coordError: NSError?
        var ok = false
        NSFileCoordinator().coordinate(readingItemAt: projectDir, options: .forUploading, error: &coordError) { tmp in
            do {
                if fm.fileExists(atPath: zipURL.path) { try fm.removeItem(at: zipURL) }
                try fm.copyItem(at: tmp, to: zipURL)
                ok = true
            } catch { ok = false }
        }
        // clean the staged tree; keep only the zip
        try? fm.removeItem(at: projectDir)
        return (ok && coordError == nil) ? zipURL : nil
    }

    /// Move a produced zip to its final destination (copy + remove temp), overwriting if needed.
    static func move(_ from: URL, to dest: URL) -> Bool {
        let fm = FileManager.default
        do {
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: from, to: dest)
            try? fm.removeItem(at: from.deletingLastPathComponent()) // remove temp staging root
            return true
        } catch { return false }
    }

    /// The project's openable static entry (index.html), if any.
    static func indexHTML(_ cwd: String) -> URL? {
        let root = URL(fileURLWithPath: cwd)
        for cand in ["index.html", "dist/index.html", "build/index.html", "public/index.html", "src/index.html"] {
            let u = root.appendingPathComponent(cand)
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }

    // MARK: - helpers

    private static func sanitize(_ name: String) -> String {
        let cleaned = name.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: "-")
        let trimmed = cleaned.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "project" : trimmed
    }

    private static func rel(_ path: String, _ base: String) -> String {
        var b = base
        if !b.hasSuffix("/") { b += "/" }
        return path.hasPrefix(b) ? String(path.dropFirst(b.count)) : path
    }
}
