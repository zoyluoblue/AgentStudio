import SwiftUI

/// R6 — share / export. Simple "I'm done, now hand it off" actions for non-coders: export a clean
/// ZIP, reveal the folder, or open the result. No git, no terminal.
struct ShareView: View {
    @Bindable var app: AppController
    @Environment(\.lang) private var lang

    private var hasProject: Bool { app.project.cwd != nil }

    var body: some View {
        Group {
            if !hasProject {
                placeholder
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        actions
                        note
                    }
                    .padding(28)
                    .frame(maxWidth: 720, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(lang.t("分享你的作品", "Share your work")).font(.largeTitle.weight(.semibold))
            Text(app.project.name ?? "")
                .font(.callout).foregroundStyle(.secondary)
            if let cwd = app.project.cwd {
                Text(cwd).font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            actionCard(
                icon: "shippingbox", tint: .orange,
                title: lang.t("导出为 ZIP 压缩包", "Export as ZIP"),
                subtitle: lang.t("打包整个项目，方便发给别人或备份。", "Bundle the whole project to send or back up."),
                busy: app.exporting,
                primary: true
            ) { Task { await app.exportProject() } }

            actionCard(
                icon: "safari", tint: .blue,
                title: lang.t("打开成品页面", "Open the result"),
                subtitle: lang.t("在浏览器里打开 index.html 看看效果。", "Open index.html in your browser."),
                disabled: !app.hasOpenableResult()
            ) { app.openResult() }

            actionCard(
                icon: "folder", tint: .secondary,
                title: lang.t("在访达中显示", "Reveal in Finder"),
                subtitle: lang.t("打开项目所在的文件夹。", "Open the project's folder.")
            ) { app.revealProject() }
        }
    }

    private var note: some View {
        Text(lang.t("导出会自动排除 node_modules、缓存、.git 和 AgentStudio 的历史快照；如果有 dist/build 等成品目录会一并打包。",
                    "Exports automatically exclude node_modules, caches, .git, and AgentStudio's snapshots; any dist/build output is included."))
            .font(.caption).foregroundStyle(.secondary)
            .padding(.top, 2)
    }

    private func actionCard(icon: String, tint: Color, title: String, subtitle: String,
                            busy: Bool = false, disabled: Bool = false, primary: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(tint.opacity(0.14)).frame(width: 42, height: 42)
                    if busy { ProgressView().controlSize(.small) }
                    else { Image(systemName: icon).font(.title3).foregroundStyle(tint) }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.callout.weight(.semibold)).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(primary ? tint.opacity(0.5) : Color(nsColor: .separatorColor)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled || busy)
        .opacity(disabled ? 0.5 : 1)
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.and.arrow.up").font(.system(size: 30, weight: .light)).foregroundStyle(.secondary)
            Text(lang.t("尚未选择项目", "No project selected")).foregroundStyle(.secondary)
            Text(lang.t("先做点东西，再回来分享。", "Build something first, then come back to share.")).font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}
