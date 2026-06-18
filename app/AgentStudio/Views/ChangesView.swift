import SwiftUI

/// R1 — change preview + one-click rollback. Left: a timeline of content checkpoints
/// (newest first). Right: exactly what the selected checkpoint changed vs the prior state,
/// with a one-click "roll back to here". Pure-Swift snapshots, no git. See SnapshotStore.
struct ChangesView: View {
    @Bindable var app: AppController
    @Environment(\.lang) private var lang

    @State private var selected: String?
    @State private var changes: [SnapshotStore.FileChange] = []
    @State private var loading = false
    @State private var rollbackTarget: SnapshotStore.Meta?

    private var hasProject: Bool { app.project.cwd != nil }

    var body: some View {
        Group {
            if !hasProject {
                placeholder(icon: "folder.badge.questionmark",
                            title: lang.t("尚未选择项目", "No project selected"),
                            subtitle: lang.t("先在左侧「新建项目」选择一个文件夹。", "Pick a folder via “New Project” on the left."))
            } else if app.checkpoints.isEmpty {
                placeholder(icon: "clock.arrow.circlepath",
                            title: lang.t("还没有改动记录", "No changes yet"),
                            subtitle: lang.t("AI 每次改文件后，这里会出现一个可回滚的版本。", "Each time the AI edits files, a roll-backable version appears here."))
            } else {
                HStack(spacing: 0) {
                    timeline.frame(width: 250)
                    Divider()
                    detail
                }
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
        .task(id: app.project.cwd) { await app.refreshCheckpoints(); syncSelection() }
        // A new write turn (or a rollback) advances HEAD — follow it so the latest change is shown.
        .onChange(of: app.currentCheckpointId) { _, new in
            if let new { selected = new; Task { await load(new) } }
        }
        .onChange(of: app.checkpoints) { _, _ in
            if selected == nil || !app.checkpoints.contains(where: { $0.id == selected }) { syncSelection() }
        }
        .confirmationDialog(
            lang.t("回滚到这个版本？", "Roll back to this version?"),
            isPresented: Binding(get: { rollbackTarget != nil }, set: { if !$0 { rollbackTarget = nil } }),
            presenting: rollbackTarget
        ) { meta in
            Button(lang.t("回滚", "Roll back"), role: .destructive) {
                Task { await app.rollback(to: meta.id); selected = meta.id; await load(meta.id) }
            }
            Button(lang.t("取消", "Cancel"), role: .cancel) {}
        } message: { meta in
            Text(lang.t("项目文件会恢复到「\(meta.label)」时的状态，这之后的改动会被撤销。",
                        "Your files will return to the “\(meta.label)” state; any later changes are undone."))
        }
    }

    // MARK: - left timeline

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(lang.t("改动历史", "Change history")).font(.headline)
                Spacer()
                Button { Task { await app.refreshCheckpoints(); syncSelection() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help(lang.t("刷新", "Refresh"))
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            Divider()

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(app.checkpoints.enumerated()), id: \.element.id) { idx, meta in
                        row(meta, isLast: idx == app.checkpoints.count - 1)
                    }
                }
                .padding(8)
            }
        }
    }

    private func row(_ meta: SnapshotStore.Meta, isLast: Bool) -> some View {
        let isCurrent = meta.id == app.currentCheckpointId
        let isSel = meta.id == selected
        return Button {
            selected = meta.id
            Task { await load(meta.id) }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                VStack(spacing: 0) {
                    Circle()
                        .fill(isCurrent ? Color.orange : Color.secondary.opacity(0.5))
                        .frame(width: 9, height: 9)
                        .padding(.top, 3)
                    if !isLast {
                        Rectangle().fill(Color.secondary.opacity(0.25)).frame(width: 1.5).frame(maxHeight: .infinity)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(meta.label).font(.callout).lineLimit(1)
                        if isCurrent {
                            Text(lang.t("当前", "Current"))
                                .font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color.orange.opacity(0.18), in: Capsule())
                                .foregroundStyle(.orange)
                        }
                    }
                    Text(relTime(meta.ts) + " · " + lang.t("\(meta.fileCount) 个文件", "\(meta.fileCount) files"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSel ? Color.orange.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - right detail

    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let meta = app.checkpoints.first(where: { $0.id == selected }) {
                detailHeader(meta)
                Divider()
                if loading {
                    Spacer(); ProgressView().frame(maxWidth: .infinity); Spacer()
                } else if changes.isEmpty {
                    placeholder(icon: "doc.plaintext",
                                title: lang.t("这一步没有改动文件", "No file changes in this step"),
                                subtitle: meta.parent == nil
                                    ? lang.t("这是项目的初始状态。", "This is the project's initial state.")
                                    : lang.t("与上一个版本相比没有差异。", "No differences from the previous version."))
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(changes) { fileCard($0) }
                        }
                        .padding(14)
                    }
                }
            } else {
                placeholder(icon: "sidebar.left",
                            title: lang.t("选择一个版本查看改动", "Pick a version to see what changed"),
                            subtitle: "")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func detailHeader(_ meta: SnapshotStore.Meta) -> some View {
        let isCurrent = meta.id == app.currentCheckpointId
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(meta.label).font(.headline).lineLimit(1)
                Text(relTime(meta.ts)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                rollbackTarget = meta
            } label: {
                Label(lang.t("回滚到此版本", "Roll back to here"), systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(isCurrent || app.rollingBack)
            .help(isCurrent ? lang.t("已是当前状态", "Already the current state") : "")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func fileCard(_ c: SnapshotStore.FileChange) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(badge(c.kind)).font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(badgeColor(c.kind).opacity(0.16), in: Capsule())
                    .foregroundStyle(badgeColor(c.kind))
                Text(c.path).font(.system(.callout, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()
            DiffBody(lines: DiffLine.compute(before: c.before, after: c.after, lang: lang))
                .padding(.vertical, 4)
        }
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
    }

    // MARK: - helpers

    private func syncSelection() {
        if selected == nil || !app.checkpoints.contains(where: { $0.id == selected }) {
            selected = app.currentCheckpointId ?? app.checkpoints.first?.id
        }
        if let id = selected { Task { await load(id) } }
    }

    private func load(_ id: String) async {
        loading = true
        changes = await app.changes(for: id)
        loading = false
    }

    private func badge(_ k: SnapshotStore.ChangeKind) -> String {
        switch k {
        case .added: return lang.t("新增", "Added")
        case .modified: return lang.t("修改", "Modified")
        case .deleted: return lang.t("删除", "Deleted")
        }
    }
    private func badgeColor(_ k: SnapshotStore.ChangeKind) -> Color {
        switch k { case .added: return .green; case .modified: return .orange; case .deleted: return .red }
    }

    private func relTime(_ ts: TimeInterval) -> String {
        let date = Date(timeIntervalSince1970: ts)
        let fmt = RelativeDateTimeFormatter()
        fmt.locale = Locale(identifier: lang == .zh ? "zh_Hans" : "en_US")
        fmt.unitsStyle = .short
        return fmt.localizedString(for: date, relativeTo: Date())
    }

    private func placeholder(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 30, weight: .light)).foregroundStyle(.secondary)
            Text(title).foregroundStyle(.secondary)
            if !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

// MARK: - diff rendering

/// One rendered diff row. `.gap` collapses a run of unchanged lines.
struct DiffLine: Identifiable, Hashable {
    enum Kind { case add, del, ctx, gap }
    let id = UUID()
    let kind: Kind
    let text: String

    /// Build a collapsed unified diff between two file versions (either may be nil).
    /// Whole-file rewrites can be large, so context is collapsed and the total is capped.
    static func compute(before: String?, after: String?, lang: Lang, context: Int = 3, cap: Int = 600) -> [DiffLine] {
        let a = (before ?? "").isEmpty ? [] : (before ?? "").components(separatedBy: "\n")
        let b = (after ?? "").isEmpty ? [] : (after ?? "").components(separatedBy: "\n")

        if before == nil { return Array(b.map { DiffLine(kind: .add, text: $0) }.prefix(cap)) }
        if after == nil { return Array(a.map { DiffLine(kind: .del, text: $0) }.prefix(cap)) }

        let diff = b.difference(from: a)
        var removals = Set<Int>()
        var insertions: [Int: String] = [:]
        for ch in diff {
            switch ch {
            case .remove(let off, _, _): removals.insert(off)
            case .insert(let off, let el, _): insertions[off] = el
            }
        }
        var raw: [DiffLine] = []
        var bi = 0
        for (ai, line) in a.enumerated() {
            if removals.contains(ai) {
                raw.append(DiffLine(kind: .del, text: line))
            } else {
                while let ins = insertions[bi] { raw.append(DiffLine(kind: .add, text: ins)); bi += 1 }
                raw.append(DiffLine(kind: .ctx, text: line)); bi += 1
            }
        }
        while let ins = insertions[bi] { raw.append(DiffLine(kind: .add, text: ins)); bi += 1 }

        return collapse(raw, context: context, lang: lang).prefixCapped(cap, lang: lang)
    }

    /// Replace long runs of unchanged lines with a single `.gap` marker.
    private static func collapse(_ lines: [DiffLine], context: Int, lang: Lang) -> [DiffLine] {
        guard !lines.isEmpty else { return lines }
        var keep = Array(repeating: false, count: lines.count)
        for (i, l) in lines.enumerated() where l.kind != .ctx {
            for j in max(0, i - context)...min(lines.count - 1, i + context) { keep[j] = true }
        }
        var out: [DiffLine] = []
        var i = 0
        while i < lines.count {
            if keep[i] { out.append(lines[i]); i += 1; continue }
            var j = i
            while j < lines.count && !keep[j] { j += 1 }
            let n = j - i
            out.append(DiffLine(kind: .gap, text: lang.t("⋯ \(n) 行未改动", "⋯ \(n) unchanged lines")))
            i = j
        }
        return out
    }
}

private extension Array where Element == DiffLine {
    func prefixCapped(_ cap: Int, lang: Lang) -> [DiffLine] {
        guard count > cap else { return self }
        return Array(prefix(cap)) + [DiffLine(kind: .gap, text: lang.t("…改动过大，已截断", "…diff too large, truncated"))]
    }
}

/// Renders diff lines as a compact, color-coded monospaced block.
private struct DiffBody: View {
    let lines: [DiffLine]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(lines) { line in
                HStack(alignment: .top, spacing: 6) {
                    Text(gutter(line.kind)).frame(width: 12, alignment: .center).foregroundStyle(.secondary)
                    Text(line.text.isEmpty ? " " : line.text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 8).padding(.vertical, 1)
                .foregroundStyle(fg(line.kind))
                .background(bg(line.kind))
            }
        }
    }

    private func gutter(_ k: DiffLine.Kind) -> String {
        switch k { case .add: return "+"; case .del: return "−"; case .ctx: return ""; case .gap: return "" }
    }
    private func fg(_ k: DiffLine.Kind) -> Color {
        switch k {
        case .add: return .green
        case .del: return .red
        case .ctx: return .primary.opacity(0.85)
        case .gap: return .secondary
        }
    }
    private func bg(_ k: DiffLine.Kind) -> Color {
        switch k {
        case .add: return Color.green.opacity(0.10)
        case .del: return Color.red.opacity(0.10)
        case .ctx: return .clear
        case .gap: return Color.secondary.opacity(0.06)
        }
    }
}
