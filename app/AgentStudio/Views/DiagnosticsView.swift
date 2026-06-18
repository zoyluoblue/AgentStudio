import SwiftUI

/// v1.1 — connection self-check sheet. Runs `AppController.diagnose` for a lane and shows a
/// plain-language checklist with fix hints, so non-coders aren't stuck guessing why Connect failed.
struct DiagnosticsView: View {
    @Bindable var app: AppController
    let kind: AgentKind
    @Environment(\.lang) private var lang
    @Environment(\.dismiss) private var dismiss

    @State private var items: [DiagnosticItem] = []
    @State private var running = false

    private var allGood: Bool { !items.isEmpty && !items.contains { $0.status == .fail } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "stethoscope").foregroundStyle(.orange)
                Text(lang.t("连接自检", "Connection check")).font(.headline)
                Spacer()
                Button { Task { await run() } } label: {
                    if running { ProgressView().controlSize(.small) }
                    else { Image(systemName: "arrow.clockwise") }
                }
                .buttonStyle(.borderless).disabled(running).help(lang.t("重新检测", "Re-run"))
                Button(lang.t("关闭", "Close")) { dismiss() }
            }
            .padding(14)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if items.isEmpty && running {
                        HStack { ProgressView().controlSize(.small); Text(lang.t("检测中…", "Checking…")).foregroundStyle(.secondary) }
                            .frame(maxWidth: .infinity).padding(.top, 30)
                    }
                    ForEach(items) { row($0) }
                    if allGood {
                        Label(lang.t("一切就绪,可以直接发消息了。", "All set — you can start chatting."), systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green).font(.callout).padding(.top, 4)
                    }
                }
                .padding(14)
            }
        }
        .frame(width: 480, height: 440)
        .task { await run() }
    }

    private func run() async {
        running = true
        items = await app.diagnose(kind)
        running = false
    }

    private func row(_ item: DiagnosticItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon(item.status)).foregroundStyle(color(item.status)).font(.callout).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.title).font(.callout.weight(.medium))
                    Text(item.detail).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
                if let fix = item.fix, item.status != .ok, item.status != .info {
                    Text(fix).font(.caption).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(color(item.status).opacity(item.status == .ok || item.status == .info ? 0.06 : 0.10),
                    in: RoundedRectangle(cornerRadius: 9))
    }

    private func icon(_ s: DiagnosticItem.Status) -> String {
        switch s {
        case .ok: return "checkmark.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .fail: return "xmark.circle.fill"
        case .info: return "info.circle"
        }
    }
    private func color(_ s: DiagnosticItem.Status) -> Color {
        switch s {
        case .ok: return .green
        case .warn: return .orange
        case .fail: return .red
        case .info: return .secondary
        }
    }
}
