import SwiftUI

/// Saved conversations + full-text search. Click a row to resume it into the live chat.
struct HistoryView: View {
    @Bindable var app: AppController
    let onOpenChat: () -> Void
    @Environment(\.lang) private var lang

    @State private var metas: [SessionMeta] = []
    @State private var query = ""
    @State private var hits: [SearchHit] = []

    private var searching: Bool { !query.trimmed.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(lang.t("搜索所有对话…", "Search all conversations…"), text: $query)
                    .textFieldStyle(.plain)
                    .onChange(of: query) { _, q in Task { hits = await HistoryStore.shared.search(q) } }
            }
            .padding(10)
            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if searching {
                        ForEach(hits) { hit in searchRow(hit) }
                        if hits.isEmpty { empty(lang.t("没有匹配的内容", "No matches")) }
                    } else {
                        ForEach(metas) { meta in historyRow(meta) }
                        if metas.isEmpty { empty(lang.t("还没有保存的对话", "No saved conversations yet")) }
                    }
                }
                .padding(12)
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
        .task { await reload() }
    }

    private func reload() async { metas = await HistoryStore.shared.list() }

    private func historyRow(_ meta: SessionMeta) -> some View {
        Button {
            Task {
                if let s = await HistoryStore.shared.get(meta.id) { app.resume(s); onOpenChat() }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: meta.mode == .collab ? "person.2" : "person")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(meta.title).font(.body).lineLimit(1)
                    Text("\(meta.projectName) · \(meta.messageCount) \(lang.t("条", "msgs")) · \(relativeTime(meta.updatedAt))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(lang.t("删除", "Delete"), role: .destructive) {
                Task { await HistoryStore.shared.remove(meta.id); await reload() }
            }
        }
    }

    private func searchRow(_ hit: SearchHit) -> some View {
        Button {
            Task {
                if let s = await HistoryStore.shared.get(hit.sessionId) { app.resume(s, focus: hit.messageId); onOpenChat() }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(hit.sessionTitle).font(.callout.weight(.medium)).lineLimit(1)
                Text(hit.snippet).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }

    private func empty(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 40)
    }

    private func relativeTime(_ ms: Int) -> String {
        let date = Date(timeIntervalSince1970: Double(ms) / 1000)
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: lang == .en ? "en_US" : "zh_CN")
        return f.localizedString(for: date, relativeTo: Date())
    }
}
