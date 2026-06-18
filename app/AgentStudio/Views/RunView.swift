import SwiftUI
import WebKit

/// R2 + R3 — one-click run, live preview, and runtime self-heal. Detects how the project starts,
/// runs it, streams logs, shows the result in an embedded web view, captures runtime/visual
/// problems (JS errors, failed loads, blank renders, build errors) and offers one-click auto-fix.
struct RunView: View {
    @Bindable var app: AppController
    @Environment(\.lang) private var lang
    @State private var showLogs = false
    @State private var reloadToken = 0
    @State private var webView: WKWebView?

    private var run: RunState { app.run }
    private var hasProject: Bool { app.project.cwd != nil }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if !app.runIssues.isEmpty { issuesBar; Divider() }
            preview
            if showLogs && !run.logs.isEmpty {
                Divider()
                logPanel
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
        .task(id: app.project.cwd) { await app.detectRunPlan() }
        .onChange(of: run.url) { _, _ in reloadToken += 1 }            // dev server came up → load it
        .onChange(of: run.reloadNonce) { _, _ in reloadToken += 1 }    // self-heal asked for a reload
        .onChange(of: run.status) { _, s in if s == .failed { showLogs = true } }
    }

    // MARK: - header

    private var header: some View {
        HStack(spacing: 10) {
            statusDot
            VStack(alignment: .leading, spacing: 1) {
                Text(planTitle).font(.callout.weight(.medium)).lineLimit(1)
                if !run.message.isEmpty {
                    Text(run.message).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            actions
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    @ViewBuilder private var actions: some View {
        if app.runPreviewURL() != nil {
            Button { reloadToken += 1 } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless).help(lang.t("刷新", "Reload"))
            Button { snapshot() } label: { Image(systemName: "camera") }
                .buttonStyle(.borderless).help(lang.t("截图", "Screenshot"))
                .disabled(webView == nil)
        }
        if let u = run.url, let url = URL(string: u) {
            Button { NSWorkspace.shared.open(url) } label: { Image(systemName: "safari") }
                .buttonStyle(.borderless).help(lang.t("在浏览器打开", "Open in browser"))
        }
        if !run.logs.isEmpty {
            Button { showLogs.toggle() } label: {
                Image(systemName: "list.bullet.rectangle")
                    .foregroundStyle(showLogs ? Color.orange : Color.secondary)
            }
            .buttonStyle(.borderless).help(lang.t("日志", "Logs"))
        }

        if run.isActive {
            Button(role: .destructive) { app.stopRun() } label: {
                Label(lang.t("停止", "Stop"), systemImage: "stop.fill")
            }
            .buttonStyle(.bordered)
        } else {
            Button { app.startRun(); showLogs = run.plan?.kind != .staticSite } label: {
                Label(lang.t("运行", "Run"), systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent).tint(.orange)
            .disabled(run.plan == nil)
        }
    }

    private var statusDot: some View {
        Circle().fill(statusColor).frame(width: 9, height: 9)
    }
    private var statusColor: Color {
        switch run.status {
        case .running: return .green
        case .installing, .starting: return .orange
        case .failed: return .red
        case .stopped, .idle: return .secondary.opacity(0.5)
        }
    }
    private var planTitle: String {
        guard let plan = run.plan else { return lang.t("未检测到可运行内容", "Nothing runnable detected") }
        switch plan.kind {
        case .node, .python: return plan.label
        case .staticSite: return lang.t("静态页面 · \(plan.label)", "Static page · \(plan.label)")
        }
    }

    // MARK: - R3 issues bar

    private var issuesBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(lang.t("检测到 \(app.runIssues.count) 个运行时问题", "Found \(app.runIssues.count) runtime issue(s)"))
                    .font(.callout.weight(.medium))
                Spacer()
                Button { app.clearRunIssues() } label: { Text(lang.t("忽略", "Dismiss")) }
                    .buttonStyle(.borderless).font(.caption)
                Button {
                    Task { await app.selfHeal() }
                } label: {
                    if app.healing { ProgressView().controlSize(.small) }
                    else { Label(lang.t("自动修复", "Auto-fix"), systemImage: "bandage") }
                }
                .buttonStyle(.borderedProminent).tint(.orange)
                .disabled(app.healing || app.busy.any || !app.laneReady(.codex))
                .help(app.laneReady(.codex) ? "" : lang.t("先连接右栏的执行方", "Connect the executor lane first"))
            }
            ForEach(app.runIssues.prefix(4)) { issue in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(issue.kind.label(lang))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.orange.opacity(0.16), in: Capsule())
                        .foregroundStyle(.orange)
                    Text(issue.message).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            if app.runIssues.count > 4 {
                Text(lang.t("…还有 \(app.runIssues.count - 4) 个", "…and \(app.runIssues.count - 4) more"))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.orange.opacity(0.06))
    }

    // MARK: - preview

    @ViewBuilder private var preview: some View {
        if !hasProject {
            placeholder(icon: "folder.badge.questionmark",
                        title: lang.t("尚未选择项目", "No project selected"),
                        subtitle: lang.t("先在左侧「新建项目」选择一个文件夹。", "Pick a folder via “New Project” on the left."))
        } else if let url = app.runPreviewURL() {
            RunWebView(url: url, token: reloadToken, lang: lang,
                       onIssue: { app.addRunIssue($0, $1) },
                       onWebView: { web in DispatchQueue.main.async { webView = web } })
        } else if run.isActive {
            VStack(spacing: 10) {
                ProgressView()
                Text(lang.t("启动中，等待页面…", "Starting up, waiting for the page…")).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if run.plan == nil {
            placeholder(icon: "play.slash",
                        title: lang.t("还没有可运行的内容", "Nothing to run yet"),
                        subtitle: lang.t("让 AI 先做出一个页面或应用，这里就能一键运行。", "Have the AI build a page or app first, then run it here."),
                        action: (lang.t("重新检测", "Re-detect"), { Task { await app.detectRunPlan() } }))
        } else {
            placeholder(icon: "play.circle",
                        title: lang.t("点击「运行」查看效果", "Hit “Run” to see it live"),
                        subtitle: run.plan.map { runHint($0) } ?? "")
        }
    }

    private func runHint(_ plan: ProjectRunner.Plan) -> String {
        switch plan.kind {
        case .node:
            return plan.needsInstall
                ? lang.t("首次运行会自动安装依赖，可能要等一会儿。", "First run auto-installs dependencies — it may take a moment.")
                : lang.t("将启动开发服务器：\(plan.label)", "Will start the dev server: \(plan.label)")
        case .python: return lang.t("将运行：\(plan.label)", "Will run: \(plan.label)")
        case .staticSite: return lang.t("将直接预览页面。", "Will preview the page directly.")
        }
    }

    // MARK: - logs

    private var logPanel: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(run.logs.enumerated()), id: \.offset) { i, line in
                        Text(line.isEmpty ? " " : line)
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(i)
                    }
                }
                .padding(8)
            }
            .frame(height: 200)
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: run.logs.count) { _, c in
                if c > 0 { withAnimation(.linear(duration: 0.1)) { proxy.scrollTo(c - 1, anchor: .bottom) } }
            }
        }
    }

    // MARK: - screenshot (visual aid)

    private func snapshot() {
        guard let web = webView, let cwd = app.project.cwd else { return }
        let cfg = WKSnapshotConfiguration()
        web.takeSnapshot(with: cfg) { image, _ in
            guard let image,
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { return }
            let dir = URL(fileURLWithPath: cwd).appendingPathComponent(".agentstudio/screenshots")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("shot-\(Int(Date().timeIntervalSince1970)).png")
            if (try? png.write(to: url)) != nil { NSWorkspace.shared.open(url) }
        }
    }

    // MARK: - helpers

    private func placeholder(icon: String, title: String, subtitle: String,
                             action: (String, () -> Void)? = nil) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 30, weight: .light)).foregroundStyle(.secondary)
            Text(title).foregroundStyle(.secondary)
            if !subtitle.isEmpty {
                Text(subtitle).font(.caption).foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center).frame(maxWidth: 360)
            }
            if let action {
                Button(action.0, action: action.1).buttonStyle(.bordered).padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

/// Loads a local file URL or a live http(s) URL, and installs a JS bridge that reports runtime
/// problems (errors, failed resources, blank renders) plus navigation failures back to the app.
private struct RunWebView: NSViewRepresentable {
    let url: URL
    let token: Int
    let lang: Lang
    let onIssue: (RunIssue.Kind, String) -> Void
    let onWebView: (WKWebView) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        let ucc = WKUserContentController()
        ucc.add(context.coordinator, name: "issues")
        ucc.addUserScript(WKUserScript(source: Self.bridgeJS, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        cfg.userContentController = ucc
        let web = WKWebView(frame: .zero, configuration: cfg)
        web.navigationDelegate = context.coordinator
        onWebView(web)
        context.coordinator.apply(url: url, token: token, to: web)
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        context.coordinator.apply(url: url, token: token, to: web)
    }

    func makeCoordinator() -> Coordinator { Coordinator(lang: lang, onIssue: onIssue) }

    /// Injected at document start: patch console.error, catch errors / rejections / resource
    /// failures, and forward them to Swift.
    private static let bridgeJS = """
    (function(){
      function send(t,m){ try{ window.webkit.messageHandlers.issues.postMessage({type:t,msg:String(m)}); }catch(e){} }
      window.addEventListener('error', function(e){
        if(e && e.target && e.target!==window && (e.target.src||e.target.href)){
          var u=e.target.src||e.target.href; if(/favicon|\\.map(\\?|$)/i.test(u)) return; send('resource', u);
        } else { send('js', (e&&e.message)?e.message:'Script error'); }
      }, true);
      window.addEventListener('unhandledrejection', function(e){
        var r=e&&e.reason; send('promise', (r&&(r.stack||r.message))?(r.stack||r.message):String(r));
      });
      var _e=console.error;
      console.error=function(){ try{ send('console', Array.prototype.slice.call(arguments).map(String).join(' ')); }catch(x){} _e.apply(console, arguments); };
    })();
    """

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        private let lang: Lang
        private let onIssue: (RunIssue.Kind, String) -> Void
        private var lastURL: URL?
        private var lastToken = -1
        private var retries = 0

        init(lang: Lang, onIssue: @escaping (RunIssue.Kind, String) -> Void) {
            self.lang = lang
            self.onIssue = onIssue
        }

        func apply(url: URL, token: Int, to web: WKWebView) {
            guard lastURL != url || lastToken != token else { return }
            lastURL = url
            lastToken = token
            retries = 0
            load(url, into: web)
        }

        private func load(_ url: URL, into web: WKWebView) {
            if url.isFileURL { web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent()) }
            else { web.load(URLRequest(url: url)) }
        }

        // Runtime errors from the page.
        func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String, let msg = body["msg"] as? String else { return }
            let map: [String: RunIssue.Kind] = ["js": .js, "console": .console, "promise": .promise, "resource": .resource]
            guard let kind = map[type] else { return }
            let text = kind == .resource ? lang.t("无法加载资源：\(msg)", "Failed to load resource: \(msg)") : msg
            onIssue(kind, text)
        }

        // Page loaded — after a beat (so SPAs can mount), check whether anything actually rendered
        // (visual: blank-page detection).
        func webView(_ web: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self, weak web] in
                guard let self, let web else { return }
                let js = "(function(){var b=document.body; if(!b) return true; var t=(b.innerText||'').trim(); " +
                         "var m=document.querySelector('img,canvas,svg,video,input,button,a'); return t.length<2 && !m;})()"
                web.evaluateJavaScript(js) { result, _ in
                    guard let blank = result as? Bool, blank else { return }
                    self.onIssue(.blank, self.lang.t("页面渲染为空白，没有可见内容。", "The page rendered blank — nothing visible."))
                }
            }
        }

        // Failed to load — for a live server this is often a boot race, so retry briefly first.
        func webView(_ web: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            handleLoadFailure(web, error)
        }
        func webView(_ web: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            handleLoadFailure(web, error)
        }

        private func handleLoadFailure(_ web: WKWebView, _ error: Error) {
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return } // superseded load
            if let url = lastURL, !url.isFileURL, retries < 2 {
                retries += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self, weak web] in
                    guard let self, let web else { return }
                    self.load(url, into: web)
                }
                return
            }
            onIssue(.navigation, lang.t("页面打不开：\(error.localizedDescription)", "Page failed to load: \(error.localizedDescription)"))
        }
    }
}
