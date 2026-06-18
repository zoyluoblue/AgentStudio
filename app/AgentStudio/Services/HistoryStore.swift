import Foundation

/// Persisted conversation store: one JSON file per session under history/.
/// Powers the History view and cross-session Search. Saves are debounced so the
/// live transcript survives crashes without thrashing the disk.
///
/// An actor so the orchestrator (recording messages) and the UI (listing / searching)
/// can touch it concurrently without races. Mirrors studio/src/main/store.ts.
actor HistoryStore {
    static let shared = HistoryStore()

    private let dir = AppPaths.historyDir
    private var current: Session?
    private var saveTask: Task<Void, Never>?

    // ---- session lifecycle ----

    /// Begin a fresh (empty) session — only hits disk once it has messages.
    func startSession(projectCwd: String, projectName: String, mode: Mode) {
        flushNow()
        let now = nowMillis()
        current = Session(
            id: Self.genId(), projectCwd: projectCwd, projectName: projectName, mode: mode,
            title: "", createdAt: now, updatedAt: now, messageCount: 0, messages: []
        )
    }

    /// Make an existing (loaded) session the live one — used by "继续对话".
    func adoptSession(_ s: Session) {
        flushNow()
        current = s
    }

    /// Upsert a message into the live session (by id) and schedule a save.
    func recordMessage(_ m: ChatMessage) {
        guard var c = current else { return }
        if let i = c.messages.firstIndex(where: { $0.id == m.id }) {
            c.messages[i] = m
        } else {
            c.messages.append(m)
        }
        if c.title.isEmpty, m.role == .user, !m.text.trimmed.isEmpty {
            c.title = String(m.text.trimmed.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).prefix(48))
        }
        c.updatedAt = nowMillis()
        current = c
        scheduleSave()
    }

    func setMode(_ mode: Mode) {
        current?.mode = mode
    }

    // ---- persistence ----

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await self?.flushNow()
        }
    }

    /// Persist the live session now (no-op while it has no messages).
    func flush() { flushNow() }

    private func flushNow() {
        saveTask?.cancel()
        saveTask = nil
        guard var c = current, !c.messages.isEmpty else { return }
        c.messageCount = c.messages.count
        current = c
        do {
            let data = try JSONEncoder().encode(c)
            try data.write(to: fileFor(c.id), options: .atomic)
        } catch {
            Log.shared.event("history.save.error", ["err": "\(error)"])
        }
    }

    // ---- queries ----

    func list() -> [SessionMeta] {
        var metas: [SessionMeta] = []
        var seen = Set<String>()
        for id in sessionIds() {
            if let s = readSession(id), !s.messages.isEmpty {
                metas.append(s.meta)
                seen.insert(id)
            }
        }
        if let c = current, !c.messages.isEmpty, !seen.contains(c.id) {
            metas.append(c.meta)
        }
        return metas.sorted { $0.updatedAt > $1.updatedAt }
    }

    func get(_ id: String) -> Session? { readSession(id) }

    func remove(_ id: String) {
        try? FileManager.default.removeItem(at: fileFor(id))
        if current?.id == id { current = nil }
        Log.shared.event("history.delete", ["id": id])
    }

    func rename(_ id: String, title: String) {
        let t = String(title.trimmed.prefix(80))
        guard !t.isEmpty else { return }
        if current?.id == id {
            current?.title = t
            flushNow()
            return
        }
        guard var s = readSession(id) else { return }
        s.title = t
        try? JSONEncoder().encode(s).write(to: fileFor(id), options: .atomic)
    }

    func search(_ query: String) -> [SearchHit] {
        let q = query.trimmed.lowercased()
        guard !q.isEmpty else { return [] }
        var hits: [SearchHit] = []
        var seen = Set<String>()

        func scan(_ s: Session) {
            for m in s.messages where m.role != .system && !m.text.isEmpty {
                guard let range = m.text.lowercased().range(of: q) else { continue }
                let idx = m.text.lowercased().distance(from: m.text.lowercased().startIndex, to: range.lowerBound)
                hits.append(SearchHit(
                    sessionId: s.id, sessionTitle: s.title.isEmpty ? "（未命名对话）" : s.title,
                    projectName: s.projectName, messageId: m.id, n: m.n, role: m.role,
                    lane: m.lane, ts: m.ts, snippet: Self.snippet(m.text, idx, q.count)
                ))
            }
        }

        for id in sessionIds() where !seen.contains(id) {
            seen.insert(id)
            if let s = readSession(id) { scan(s) }
        }
        if let c = current, !seen.contains(c.id) { scan(c) }
        return Array(hits.sorted { $0.ts > $1.ts }.prefix(200))
    }

    // ---- helpers ----

    private func fileFor(_ id: String) -> URL { dir.appendingPathComponent("\(id).json") }

    private func sessionIds() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return files.filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) }
    }

    private func readSession(_ id: String) -> Session? {
        if let c = current, c.id == id { return c } // freshest copy
        guard let data = try? Data(contentsOf: fileFor(id)) else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    private static func snippet(_ text: String, _ idx: Int, _ len: Int) -> String {
        let chars = Array(text)
        let start = max(0, idx - 30)
        let end = min(chars.count, idx + len + 60)
        let pre = start > 0 ? "…" : ""
        let post = end < chars.count ? "…" : ""
        let mid = String(chars[start..<end])
        return (pre + mid + post).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmed
    }

    private static func genId() -> String {
        "s_\(base36(nowMillis()))_\(base36(Int.random(in: 0..<1_000_000)))"
    }

    private static func base36(_ n: Int) -> String {
        String(n, radix: 36)
    }
}
