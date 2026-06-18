import SwiftUI
import WebKit

/// In-pane preview: flip a lane from "对话" to "预览" to look at the project's HTML pages and
/// images without leaving the chat. Pick a file from the chips; HTML renders in a web view,
/// images render fit-to-pane.
struct PanePreviewView: View {
    @Bindable var app: AppController
    @Environment(\.lang) private var lang

    @State private var files: [String] = []
    @State private var selected: String?
    @State private var reloadToken = 0

    private var cwd: String? { app.project.cwd }

    var body: some View {
        VStack(spacing: 0) {
            if cwd == nil {
                placeholder("folder.badge.questionmark", lang.t("尚未选择项目", "No project selected"), nil)
            } else if files.isEmpty {
                placeholder("photo.on.rectangle.angled",
                            lang.t("没有可预览的 HTML / 图片", "No HTML or images to preview"),
                            (lang.t("重新扫描", "Rescan"), { reload() }))
            } else {
                chips
                Divider()
                content
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
        .task(id: app.project.cwd) { reload() }
        // Refresh the file list + reload the preview whenever the AI writes (a new checkpoint lands).
        .onChange(of: app.currentCheckpointId) { _, _ in reload() }
    }

    // MARK: file chips

    private var chips: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(files, id: \.self) { f in chip(f) }
                }
                .padding(.horizontal, 8)
            }
            Button { reload() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless).help(lang.t("重新扫描", "Rescan")).padding(.trailing, 6)
            if selected != nil {
                Button { reloadToken += 1 } label: { Image(systemName: "arrow.clockwise.circle") }
                    .buttonStyle(.borderless).help(lang.t("刷新预览", "Reload preview")).padding(.trailing, 8)
            }
        }
        .frame(height: 38)
    }

    private func chip(_ f: String) -> some View {
        let isSel = f == selected
        return Button { selected = f; reloadToken += 1 } label: {
            HStack(spacing: 5) {
                Image(systemName: ProjectFiles.isHTML(f) ? "doc.richtext" : "photo")
                    .font(.caption2)
                Text((f as NSString).lastPathComponent).font(.caption).lineLimit(1)
            }
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(isSel ? Color.orange.opacity(0.18) : Color(nsColor: .controlBackgroundColor),
                        in: Capsule())
            .foregroundStyle(isSel ? Color.orange : Color.primary)
            .overlay(Capsule().strokeBorder(isSel ? Color.orange.opacity(0.5) : Color(nsColor: .separatorColor)))
        }
        .buttonStyle(.plain)
        .help(f)
    }

    // MARK: preview body

    @ViewBuilder private var content: some View {
        if let rel = selected, let cwd {
            let url = URL(fileURLWithPath: cwd).appendingPathComponent(rel)
            if ProjectFiles.isHTML(rel) {
                PreviewWebView(url: url, token: reloadToken)
            } else {
                ImagePreview(url: url, token: reloadToken)
            }
        } else {
            placeholder("hand.tap", lang.t("点上面的文件进行预览", "Tap a file above to preview"), nil)
        }
    }

    // MARK: helpers

    private func reload() {
        guard let cwd else { files = []; selected = nil; return }
        files = ProjectFiles.previewableFiles(cwd)
        if let s = selected, !files.contains(s) { selected = nil }
        if selected == nil { selected = files.first }
        reloadToken += 1
    }

    private func placeholder(_ icon: String, _ title: String, _ action: (String, () -> Void)?) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 28, weight: .light)).foregroundStyle(.secondary)
            Text(title).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let action {
                Button(action.0, action: action.1).buttonStyle(.bordered).controlSize(.small).padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

/// Fit-to-pane image preview (loaded fresh on token change so edits show up).
private struct ImagePreview: View {
    let url: URL
    let token: Int

    var body: some View {
        Group {
            if let img = NSImage(contentsOf: url) {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(12)
            } else {
                Text("⚠️").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .id(token) // reload the NSImage when asked
    }
}

/// Minimal local-file web view that reloads on token change.
private struct PreviewWebView: NSViewRepresentable {
    let url: URL
    let token: Int

    func makeNSView(context: Context) -> WKWebView {
        let web = WKWebView()
        context.coordinator.apply(url: url, token: token, to: web)
        return web
    }
    func updateNSView(_ web: WKWebView, context: Context) {
        context.coordinator.apply(url: url, token: token, to: web)
    }
    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private var last: URL?
        private var lastToken = -1
        func apply(url: URL, token: Int, to web: WKWebView) {
            guard last != url || lastToken != token else { return }
            last = url; lastToken = token
            web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }
}
