import SwiftUI

/// Left navigation rail — text labels (bilingual).
struct SidebarView: View {
    @Binding var view: MainView
    let onNewProject: () -> Void
    @Environment(\.lang) private var lang

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").foregroundStyle(.orange)
                Text("AgentStudio").font(.headline)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            row(lang.t("新建项目", "New Project"), active: false, action: onNewProject)

            Divider().padding(.horizontal, 12).padding(.vertical, 4)

            row(lang.t("开始", "Start"), active: view == .start) { view = .start }
            row(lang.t("对话", "Chat"), active: view == .chat) { view = .chat }
            row(lang.t("改动", "Changes"), active: view == .changes) { view = .changes }
            row(lang.t("历史", "History"), active: view == .history) { view = .history }
            row(lang.t("记忆", "Memory"), active: view == .memory) { view = .memory }
            row(lang.t("运行", "Run"), active: view == .run) { view = .run }
            row(lang.t("分享", "Share"), active: view == .share) { view = .share }

            Spacer()

            row(lang.t("设置", "Settings"), active: view == .settings) { view = .settings }
                .padding(.bottom, 10)
        }
        .frame(width: 152)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func row(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(active ? Color.orange.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 7))
                .foregroundStyle(active ? Color.orange : Color.primary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }
}
