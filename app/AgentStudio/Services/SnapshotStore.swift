import Foundation

/// Pure-Swift content checkpoints — the foundation for R1 (change preview + one-click
/// rollback) and later self-heal/rollback features. NO git dependency: every snapshot
/// copies the project's non-ignored source files into `.agentstudio/snapshots/<id>/files/`
/// plus a tiny `manifest.json`. A `HEAD` file records the current checkpoint so diffs and
/// rollbacks stay correct even after the user jumps back in time.
///
/// All methods are pure filesystem work and safe to call off the main actor.
enum SnapshotStore {
    /// One checkpoint's metadata. `parent` is the checkpoint that was HEAD when this one was
    /// taken — diffs are computed against the parent (not merely the chronologically previous
    /// snapshot), so rolling back and then editing still produces a correct "what changed".
    struct Meta: Codable, Sendable, Identifiable, Hashable {
        var id: String
        var label: String
        var ts: TimeInterval
        var fileCount: Int
        var parent: String?
    }

    enum ChangeKind: String, Codable, Sendable { case added, modified, deleted }

    struct FileChange: Sendable, Identifiable, Hashable {
        var id: String { path }
        var path: String
        var kind: ChangeKind
        var before: String?
        var after: String?
    }

    // MARK: - storage layout

    private static let dirName = ".agentstudio"

    private static func snapsRoot(_ cwd: String) -> URL {
        URL(fileURLWithPath: cwd).appendingPathComponent(dirName, isDirectory: true)
            .appendingPathComponent("snapshots", isDirectory: true)
    }
    private static func snapDir(_ cwd: String, _ id: String) -> URL {
        snapsRoot(cwd).appendingPathComponent(id, isDirectory: true)
    }
    private static func filesDir(_ cwd: String, _ id: String) -> URL {
        snapDir(cwd, id).appendingPathComponent("files", isDirectory: true)
    }
    private static func headURL(_ cwd: String) -> URL {
        snapsRoot(cwd).appendingPathComponent("HEAD")
    }

    /// The current checkpoint id (the one disk currently reflects), or nil if none yet.
    static func head(_ cwd: String) -> String? {
        (try? String(contentsOf: headURL(cwd), encoding: .utf8))?.trimmed.nonEmpty
    }
    private static func setHead(_ cwd: String, _ id: String) {
        try? id.write(to: headURL(cwd), atomically: true, encoding: .utf8)
    }

    // MARK: - create

    /// Capture the current project state as a new checkpoint. Returns its metadata, or nil
    /// if nothing could be written. Sets HEAD to the new checkpoint.
    @discardableResult
    static func snapshot(cwd: String, label: String) -> Meta? {
        let parent = head(cwd)
        let files = ProjectFiles.sourceFiles(cwd)
        let ts = Date().timeIntervalSince1970
        // ms since epoch (sortable) + a short random suffix so two snapshots in the same
        // millisecond can't collide on the same folder/id.
        let id = String(format: "%015.0f", ts * 1000) + "-" + String(UUID().uuidString.prefix(6))
        let fm = FileManager.default
        let dest = filesDir(cwd, id)
        guard (try? fm.createDirectory(at: dest, withIntermediateDirectories: true)) != nil else { return nil }

        let root = URL(fileURLWithPath: cwd)
        var copied = 0
        for rel in files {
            let src = root.appendingPathComponent(rel)
            let dst = dest.appendingPathComponent(rel)
            do {
                try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: dst.path) { try? fm.removeItem(at: dst) }
                try fm.copyItem(at: src, to: dst)
                copied += 1
            } catch { continue }
        }

        let meta = Meta(id: id, label: label, ts: ts, fileCount: copied, parent: parent)
        if let data = try? JSONEncoder().encode(meta) {
            try? data.write(to: snapDir(cwd, id).appendingPathComponent("manifest.json"))
        }
        setHead(cwd, id)
        return meta
    }

    // MARK: - list

    /// All checkpoints, newest first.
    static func list(cwd: String) -> [Meta] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: snapsRoot(cwd), includingPropertiesForKeys: nil) else { return [] }
        var metas: [Meta] = []
        for e in entries {
            let manifest = e.appendingPathComponent("manifest.json")
            guard let data = try? Data(contentsOf: manifest),
                  let m = try? JSONDecoder().decode(Meta.self, from: data) else { continue }
            metas.append(m)
        }
        return metas.sorted { $0.ts > $1.ts }
    }

    // MARK: - diff

    /// What checkpoint `id` changed relative to its parent (added / modified / deleted files,
    /// each carrying before/after content). If the checkpoint has no parent it's the baseline,
    /// so everything reads as "added".
    static func changes(cwd: String, id: String) -> [FileChange] {
        guard let meta = list(cwd: cwd).first(where: { $0.id == id }) else { return [] }
        return diff(cwd: cwd, from: meta.parent, to: id)
    }

    /// Diff between two checkpoints (either side may be nil → empty tree). Add/delete/modify is
    /// decided by file *presence*, so binary or empty files still surface; content (nil for
    /// non-UTF-8 files) only drives the inline diff body.
    static func diff(cwd: String, from fromId: String?, to toId: String?) -> [FileChange] {
        let before = fromId.map { Set(storedFiles(cwd, $0)) } ?? []
        let after = toId.map { Set(storedFiles(cwd, $0)) } ?? []
        var out: [FileChange] = []
        for rel in before.union(after).sorted() {
            let inB = before.contains(rel), inA = after.contains(rel)
            let b = inB ? fromId.flatMap { readStored(cwd, $0, rel) } : nil
            let a = inA ? toId.flatMap { readStored(cwd, $0, rel) } : nil
            if !inB, inA { out.append(.init(path: rel, kind: .added, before: nil, after: a)) }
            else if inB, !inA { out.append(.init(path: rel, kind: .deleted, before: b, after: nil)) }
            else if inB, inA, a != b { out.append(.init(path: rel, kind: .modified, before: b, after: a)) }
        }
        return out
    }

    // MARK: - restore

    /// Make the project on disk exactly match checkpoint `id`: write back every stored file and
    /// delete current source files that the checkpoint didn't have. Sets HEAD to `id`.
    @discardableResult
    static func restore(cwd: String, id: String) -> Bool {
        let fm = FileManager.default
        let stored = Set(storedFiles(cwd, id))
        guard !stored.isEmpty || head(cwd) != nil else { return false }
        let root = URL(fileURLWithPath: cwd)

        // 1. remove current source files absent from the checkpoint
        for rel in ProjectFiles.sourceFiles(cwd) where !stored.contains(rel) {
            try? fm.removeItem(at: root.appendingPathComponent(rel))
        }
        // 2. write back the checkpoint's files
        let from = filesDir(cwd, id)
        for rel in stored {
            let src = from.appendingPathComponent(rel)
            let dst = root.appendingPathComponent(rel)
            do {
                try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: dst.path) { try? fm.removeItem(at: dst) }
                try fm.copyItem(at: src, to: dst)
            } catch { continue }
        }
        setHead(cwd, id)
        return true
    }

    // MARK: - housekeeping

    /// Keep only the most recent `keep` checkpoints on disk.
    static func prune(cwd: String, keep: Int = 40) {
        let metas = list(cwd: cwd)
        guard metas.count > keep else { return }
        let fm = FileManager.default
        for m in metas[keep...] { try? fm.removeItem(at: snapDir(cwd, m.id)) }
    }

    // MARK: - stored-file helpers

    private static func storedFiles(_ cwd: String, _ id: String) -> [String] {
        let base = filesDir(cwd, id).standardizedFileURL
        let fm = FileManager.default
        guard let en = fm.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        let basePath = base.path
        var out: [String] = []
        for case let u as URL in en {
            let isFile = (try? u.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
            guard isFile else { continue }
            let p = u.standardizedFileURL.path
            if p.hasPrefix(basePath + "/") { out.append(String(p.dropFirst(basePath.count + 1))) }
        }
        return out
    }

    private static func readStored(_ cwd: String, _ id: String, _ rel: String) -> String? {
        try? String(contentsOf: filesDir(cwd, id).appendingPathComponent(rel), encoding: .utf8)
    }
}
