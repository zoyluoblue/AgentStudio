import AppKit
import SwiftUI

/// The two-pane chat: left = master/planner, right = slave/executor.
struct ChatView: View {
    @Bindable var app: AppController

    var body: some View {
        HStack(spacing: Theme.gutter) {
            AgentPanelView(app: app, kind: .claude)
            AgentPanelView(app: app, kind: .codex)
        }
        .padding(Theme.gutter)
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}

// MARK: - one agent's panel

enum PaneMode: Hashable { case chat, preview }

struct AgentPanelView: View {
    @Bindable var app: AppController
    let kind: AgentKind
    @Environment(\.lang) private var lang
    @State private var showDiag = false
    @State private var mode: PaneMode = .chat

    private var backend: Backend { app.backend(of: kind) }
    private var lane: Lane { app.lane(of: kind) }
    private var ready: Bool { app.laneReady(kind) }
    private var isKey: Bool { app.settings.connectMethod(for: lane) == .key }
    private var messages: [ChatMessage] { kind == .claude ? app.claudeMessages : app.codexMessages }
    /// In collab the right (codex) pane is driven by orchestration — no composer.
    private var showsComposer: Bool { !(app.collab && kind == .codex) }
    private var busy: Bool { app.collab ? app.anyBusy : app.busy[kind] }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            modeBar
            Divider()
            if mode == .chat {
                ConversationView(messages: messages, activity: app.activity[kind], accent: Theme.accent(backend))
                if showsComposer {
                    Divider()
                    ComposerView(
                        busy: busy,
                        disabled: !ready || app.project.cwd == nil,
                        placeholder: placeholder,
                        seed: kind == .claude ? $app.composerSeed : nil,
                        onSend: { app.send($0, target: kind) },
                        onStop: { app.abort(kind) }
                    )
                }
            } else {
                PanePreviewView(app: app)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(.separator))
        .sheet(isPresented: $showDiag) {
            DiagnosticsView(app: app, kind: kind).environment(\.lang, lang)
        }
    }

    /// Small "对话 / 预览" switch for this lane.
    private var modeBar: some View {
        HStack {
            Picker("", selection: $mode) {
                Text(lang.t("对话", "Chat")).tag(PaneMode.chat)
                Text(lang.t("预览", "Preview")).tag(PaneMode.preview)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 150)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    private var header: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: Theme.icon(backend)).foregroundStyle(Theme.accent(backend))

                // combined backend + connection-method choice (Claude API / OpenAI / DeepSeek / Claude Code / Codex)
                Picker("", selection: Binding(get: { app.laneOption(kind) }, set: { app.selectLaneOption(kind, $0) })) {
                    ForEach(LaneOption.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden().frame(width: 132)
                .help(lang.t("这一栏用哪个模型 / 连接方式", "This lane's provider / connection"))

                Picker("", selection: Binding(get: { app.models[kind] ?? "" }, set: { app.setModel(kind, $0) })) {
                    Text(lang.t("默认模型", "Default model")).tag("")
                    ForEach(app.modelOptions[kind] ?? []) { Text($0.label).tag($0.id) }
                }
                .labelsHidden().frame(width: 118)

                Spacer(minLength: 6)

                Button { showDiag = true } label: { Image(systemName: "stethoscope") }
                    .buttonStyle(.borderless).controlSize(.small)
                    .help(lang.t("连接自检", "Connection check"))
                connectButton
                statusDot
            }

            // API mode: aligned api_key / base_url form (both fields the same width)
            if isKey {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                    GridRow {
                        Text("api_key")
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                            .gridColumnAlignment(.trailing)
                        TextField("sk-…", text: Binding(
                            get: { app.settings.apiKeys[lane] },
                            set: { v in app.setApiKey(kind, v) }
                        ))
                        .textFieldStyle(.roundedBorder).plainTextEntry()
                        .help(lang.t("\(backend.displayName) API Key（存于钥匙串；填写后点「连接」验证）",
                                     "\(backend.displayName) API key (stored in Keychain; click Connect to validate)"))
                    }
                    GridRow {
                        Text("base_url")
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                        TextField("https://…", text: Binding(
                            get: { app.settings.useDefaultBaseURL[lane] ? AppSettings.defaultBaseURL(backend) : app.settings.baseURLs[lane] },
                            set: { v in app.setBaseURL(kind, v) }
                        ))
                        .textFieldStyle(.roundedBorder).plainTextEntry()
                        .disabled(app.settings.useDefaultBaseURL[lane])
                        .help(lang.t("API Base URL（有默认值，可覆盖）", "API base URL (default provided, can override)"))
                    }
                    GridRow {
                        Color.clear.frame(width: 1, height: 1)
                        Toggle(lang.t("使用默认 base_url", "Use default base_url"), isOn: Binding(
                            get: { app.settings.useDefaultBaseURL[lane] },
                            set: { on in app.setUseDefaultBaseURL(kind, on) }
                        ))
                        .toggleStyle(.checkbox)
                        .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder private var connectButton: some View {
        if app.connecting[kind] == true {
            ProgressView().controlSize(.small)
        } else if ready {
            Button(lang.t("断开", "Disconnect")) { app.disconnect(kind) }
                .buttonStyle(.bordered).controlSize(.small)
                .help(lang.t("断开连接（保留 Key / 登录态）", "Disconnect (keeps the key / login)"))
        } else {
            Button(lang.t("连接", "Connect")) { app.connect(kind) }
                .buttonStyle(.borderedProminent).controlSize(.small)
                .help(isKey ? lang.t("连接并自动验证 API Key", "Connect and validate the API key")
                            : lang.t("用本机登录态连接", "Connect using the local CLI login"))
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(ready ? Color.green : Color.orange)
            .frame(width: 8, height: 8)
            .help(ready ? (app.status(of: kind).detail.map { lang.t("已连接（\($0)）", "Connected (\($0))") } ?? lang.t("已连接", "Connected"))
                        : lang.t("未连接", "Not connected"))
    }

    private var placeholder: String {
        if app.project.cwd == nil { return lang.t("请先在上方选择项目文件夹", "Choose a project folder above first") }
        if !ready {
            return isKey ? lang.t("请填写 \(backend.displayName) 的 API Key 并连接", "Enter the \(backend.displayName) API key and connect")
                         : lang.t("请连接 \(backend.displayName)（无需 API Key）", "Connect \(backend.displayName) (no API key)")
        }
        if app.collab { return lang.t("描述你想做的东西，左右两栏会自动规划→执行→审查…", "Describe what you want — plan → execute → review runs automatically…") }
        // Solo: this lane works alone and does the whole job (incl. editing files).
        return lang.t("说说你想做什么，\(backend.displayName) 会独立帮你做出来…", "Tell \(backend.displayName) what you want — it'll build it for you…")
    }
}

// MARK: - conversation

/// Tracks the bottom anchor's position within the scroll viewport, to decide whether to keep
/// auto-scrolling. (macOS 14 friendly — no scroll-geometry APIs.)
private struct BottomOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct ConversationView: View {
    let messages: [ChatMessage]
    let activity: String
    let accent: Color
    @Environment(\.lang) private var lang
    /// Whether the user is parked near the bottom. Only then do we follow new output; if they've
    /// scrolled up to read, we leave them be.
    @State private var atBottom = true

    var body: some View {
        GeometryReader { outer in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if messages.isEmpty {
                            Text(lang.t("还没有对话。", "No messages yet."))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 40)
                        }
                        ForEach(messages) { MessageRow(message: $0, accent: accent) }
                        if !activity.isEmpty {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text(activity).font(.caption).foregroundStyle(.secondary)
                            }
                            .id("activity")
                        }
                        Color.clear.frame(height: 1).id("bottom")
                            .background(GeometryReader { g in
                                Color.clear.preference(key: BottomOffsetKey.self,
                                                       value: g.frame(in: .named("convo")).minY)
                            })
                    }
                    .padding(14)
                }
                .coordinateSpace(name: "convo")
                .onPreferenceChange(BottomOffsetKey.self) { y in
                    // Bottom is within view (≈ at the end) when its offset is within the viewport.
                    atBottom = y <= outer.size.height + 40
                }
                .onChange(of: messages.count) { _, _ in follow(proxy, animated: true) }
                .onChange(of: messages.last?.text) { _, _ in follow(proxy, animated: false) }
                .onChange(of: activity) { _, _ in follow(proxy, animated: false) }
            }
        }
    }

    private func follow(_ proxy: ScrollViewProxy, animated: Bool) {
        guard atBottom else { return } // user scrolled up → don't yank them down
        if animated { withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo("bottom", anchor: .bottom) } }
        else { proxy.scrollTo("bottom", anchor: .bottom) }
    }
}

struct MessageRow: View {
    let message: ChatMessage
    let accent: Color
    @Environment(\.lang) private var lang

    private var isUser: Bool { message.role == .user }
    private var isSystem: Bool { message.role == .system }

    @State private var expanded = false

    private var lineCount: Int { message.text.split(separator: "\n", omittingEmptySubsequences: false).count }
    /// Big outputs (long code / file dumps) get collapsed so one message can't take over the pane.
    private var isLong: Bool { message.text.count > 700 || lineCount > 14 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(label).font(.caption.weight(.semibold)).foregroundStyle(labelColor)
                Spacer()
                if isLong {
                    Text(lang.t("\(lineCount) 行", "\(lineCount) lines")).font(.caption2).foregroundStyle(.tertiary)
                }
                Text("#\(message.n)").font(.caption2).foregroundStyle(.tertiary)
            }
            bodyView
        }
    }

    @ViewBuilder private var bodyView: some View {
        let display = message.text.isEmpty && message.pending == true ? "…" : message.text
        if isLong {
            VStack(alignment: .leading, spacing: 6) {
                if expanded {
                    ScrollView { bubble(display) }
                        .frame(maxHeight: 420)        // even expanded, only a window — scroll for the rest
                } else {
                    bubble(String(display.prefix(1400)))
                        .frame(maxHeight: 168, alignment: .top)
                        .clipped()
                        .overlay(alignment: .bottom) {
                            LinearGradient(colors: [.clear, Color(nsColor: .controlBackgroundColor)],
                                           startPoint: .top, endPoint: .bottom)
                                .frame(height: 36).allowsHitTesting(false)
                        }
                }
                Button { withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() } } label: {
                    HStack(spacing: 4) {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        Text(expanded ? lang.t("收起", "Collapse")
                                      : lang.t("展开全部（\(lineCount) 行）", "Expand (\(lineCount) lines)"))
                    }
                    .font(.caption)
                }
                .buttonStyle(.plain).foregroundStyle(accent)
            }
        } else {
            bubble(display)
        }
    }

    private func bubble(_ text: String) -> some View {
        Text(renderMarkdown(text))
            .textSelection(.enabled)
            .font(.callout)
            .foregroundStyle(message.kind == .error ? Color.red : Color.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(bubbleColor, in: RoundedRectangle(cornerRadius: 10))
    }

    private var label: String {
        if isUser { return lang.t("你", "You") }
        if isSystem { return lang.t("系统", "System") }
        return message.agentName ?? lang.t("助手", "Assistant")
    }
    private var labelColor: Color { isUser ? .accentColor : (isSystem ? .secondary : accent) }
    private var bubbleColor: Color {
        if isUser { return Color.accentColor.opacity(0.12) }
        if isSystem { return Color.secondary.opacity(0.10) }
        return Color(nsColor: .textBackgroundColor).opacity(0.6)
    }
}

// MARK: - composer

struct ComposerView: View {
    let busy: Bool
    let disabled: Bool
    let placeholder: String
    var seed: Binding<String>? = nil   // guided-start drops a goal here for the planner composer
    let onSend: (String) -> Void
    let onStop: () -> Void
    @Environment(\.lang) private var lang

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(placeholder, text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(3...10)
                .focused($focused)
                .disabled(disabled)
                .onSubmit(send)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .frame(minHeight: 64, alignment: .topLeading)            // bigger, easier hit area
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(focused ? Color.accentColor.opacity(0.55) : Color(nsColor: .separatorColor)))
                .contentShape(RoundedRectangle(cornerRadius: 10))          // click anywhere in the box…
                .onTapGesture { if !disabled { focused = true } }         // …to focus the field
                .onChange(of: seed?.wrappedValue ?? "") { _, _ in consumeSeed() }
                .onAppear { consumeSeed() } // seed may already be set before the composer mounts

            if busy {
                Button(action: onStop) {
                    Image(systemName: "stop.fill").frame(width: 30, height: 30)
                }
                .buttonStyle(.borderedProminent).tint(.red)
                .help(lang.t("停止", "Stop"))
            } else {
                Button(action: send) {
                    Image(systemName: "arrow.up").frame(width: 30, height: 30)
                }
                .buttonStyle(.borderedProminent)
                .disabled(disabled || text.trimmed.isEmpty)
                .help(lang.t("发送（回车）", "Send (Return)"))
            }
        }
        .padding(10)
    }

    private func send() {
        let t = text.trimmed
        guard !t.isEmpty, !disabled else { return }
        onSend(t)
        text = ""
    }

    /// Pull a guided-start goal into the field (once), if one is waiting.
    private func consumeSeed() {
        guard let v = seed?.wrappedValue, !v.isEmpty else { return }
        text = v
        seed?.wrappedValue = ""
        focused = true
    }
}
