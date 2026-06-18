import AppKit
import SwiftUI

/// Preferences: lane providers, proxy, appearance, memory.
/// (Per-backend connection — key / base URL / connect — lives in each pane header.)
struct SettingsView: View {
    @Bindable var app: AppController
    @Bindable var store: SettingsStore
    @Environment(\.lang) private var lang
    @EnvironmentObject private var updater: UpdaterController
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @State private var mcpName = ""
    @State private var mcpCommand = ""
    @State private var mcpArgs = ""

    var body: some View {
        Form {
            Section(lang.t("帮助", "Help")) {
                CheckForUpdatesButton(updater: updater)
                Button(lang.t("再看一次新手引导", "Replay the quick tour")) { hasOnboarded = false }
            }

            Section(lang.t("智能体角色", "Agent roles")) {
                Picker(lang.t("左栏 · 规划/审查", "Left · plan / review"),
                       selection: Binding(get: { app.laneOption(.claude) }, set: { app.selectLaneOption(.claude, $0) })) {
                    ForEach(LaneOption.allCases) { Text($0.label).tag($0) }
                }
                Picker(lang.t("右栏 · 执行", "Right · execute"),
                       selection: Binding(get: { app.laneOption(.codex) }, set: { app.selectLaneOption(.codex, $0) })) {
                    ForEach(LaneOption.allCases) { Text($0.label).tag($0) }
                }
                Toggle(lang.t("自动从对话中提炼长期记忆", "Auto-extract long-term memory from chats"),
                       isOn: $store.settings.autoMemory)
                Text(lang.t("每栏的 API Key / Base URL / 连接在对话页对应栏标题栏里配置。",
                            "Each lane's API key / base URL / connection is set in its pane header on the Chat page."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(lang.t("网络代理", "Network proxy")) {
                Picker(lang.t("模式", "Mode"), selection: $store.settings.proxyMode) {
                    Text(lang.t("跟随系统", "System")).tag(ProxyMode.system)
                    Text(lang.t("自定义", "Custom")).tag(ProxyMode.custom)
                    Text(lang.t("不使用", "Off")).tag(ProxyMode.none)
                }
                if store.settings.proxyMode == .custom {
                    TextField(lang.t("代理地址", "Proxy URL"), text: $store.settings.proxyUrl, prompt: Text("http://127.0.0.1:7890")).plainTextEntry()
                }
                Picker(lang.t("作用范围", "Scope"), selection: $store.settings.proxyScope) {
                    Text(lang.t("两栏都用", "Both lanes")).tag(ProxyScope.both)
                    Text(lang.t("仅左栏", "Left only")).tag(ProxyScope.master)
                    Text(lang.t("仅右栏", "Right only")).tag(ProxyScope.slave)
                }
                Text(lang.t("DeepSeek 始终直连，不走代理。", "DeepSeek always connects directly (no proxy)."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(lang.t("用量与预算", "Usage & budget")) {
                LabeledContent(lang.t("本月预计花费", "Estimated this month")) {
                    Text("≈$\(app.money(app.costMonth))").monospacedDigit()
                        .foregroundStyle(app.overBudget ? .red : .primary)
                }
                HStack {
                    Text(lang.t("每月预算（美元，0 = 不限制）", "Monthly budget (USD, 0 = off)"))
                    Spacer()
                    TextField("", value: $store.settings.monthlyBudgetUSD,
                              format: .number.precision(.fractionLength(0...2)))
                        .multilineTextAlignment(.trailing).frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                }
                if app.monthlyBudget > 0 {
                    ProgressView(value: app.budgetFraction)
                        .tint(app.overBudget ? .red : (app.budgetFraction >= 0.8 ? .orange : .green))
                }
                HStack {
                    Text(lang.t("累计 \(app.money(app.costTotal)) 美元", "Spent $\(app.money(app.costTotal)) total"))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(lang.t("清空用量记录", "Reset usage"), role: .destructive) { app.resetUsage() }
                        .controlSize(.small)
                }
                Text(lang.t("按公开价估算，仅统计 API Key 直连用量；本地 CLI 登录不计费。达到预算后会暂停新对话。",
                            "Estimated at list prices; counts API-key usage only (local CLI login isn't billed). New turns pause once the budget is hit."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(lang.t("执行能力", "Agent capabilities")) {
                Toggle(lang.t("允许 AI 运行命令(装依赖 / 跑测试 / git / 起服务)",
                              "Let the AI run commands (install deps / tests / git / dev servers)"),
                       isOn: $store.settings.allowCommands)
                Text(lang.t("开启后,执行方不只是改文件,还能在你的项目里真正执行命令、自己跑通。功能更强,但请仅对信任的项目开启。改动随时可在「改动」里回滚。",
                            "When on, the executor doesn't just edit files — it actually runs commands in your project and gets things working. More powerful; enable only for projects you trust. Any change is rollback-able under “Changes”."))
                    .font(.caption).foregroundStyle(.secondary)

                Toggle(lang.t("Anthropic(API Key)走官方 Claude Agent 引擎",
                              "Use the official Claude Agent engine for Anthropic (API key)"),
                       isOn: $store.settings.useAgentSDK)
                Text(lang.t("仅对「用 API Key 连接的 Anthropic」生效:改用官方 Claude Agent SDK(更强的智能体:原生读写改文件、子代理、会话)。需本机装有 Node;不可用时自动回退到内置引擎。OpenAI / DeepSeek 不受影响。",
                            "Applies only to Anthropic connected via API key: drives the official Claude Agent SDK (stronger agent — native file edits, subagents, sessions). Needs Node on this Mac; falls back to the built-in engine if unavailable. OpenAI / DeepSeek are unaffected."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(lang.t("MCP / 插件", "MCP / Plugins")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(lang.t("一键添加常用插件", "Add a common plugin"))
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(MCPConfig.presets) { p in
                        let added = store.settings.mcpServers.contains { $0.id == p.id }
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(lang.t(p.zhTitle, p.enTitle)).font(.callout.weight(.medium))
                                Text(lang.t(p.zhDesc, p.enDesc)).font(.caption).foregroundStyle(.secondary)
                                if let note = lang.t(p.zhNote ?? "", p.enNote ?? "").nonEmpty {
                                    Text("· " + note).font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                            Spacer()
                            Button(added ? lang.t("已添加", "Added") : lang.t("添加", "Add")) { addPreset(p) }
                                .controlSize(.small).disabled(added)
                        }
                    }
                }

                if !store.settings.mcpServers.isEmpty {
                    Divider().padding(.vertical, 2)
                }
                ForEach(store.settings.mcpServers) { s in
                    HStack(spacing: 10) {
                        Toggle("", isOn: Binding(
                            get: { s.enabled },
                            set: { on in if let i = store.settings.mcpServers.firstIndex(where: { $0.id == s.id }) { store.settings.mcpServers[i].enabled = on } }
                        )).labelsHidden()
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.id).font(.callout.weight(.medium))
                            Text(([s.command] + s.args).joined(separator: " ")).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Button(role: .destructive) { store.settings.mcpServers.removeAll { $0.id == s.id } } label: {
                            Image(systemName: "trash")
                        }.buttonStyle(.borderless)
                    }
                }
                HStack(spacing: 6) {
                    TextField(lang.t("名称", "Name"), text: $mcpName).frame(width: 90).plainTextEntry()
                    TextField(lang.t("命令", "Command"), text: $mcpCommand, prompt: Text("npx")).frame(width: 70).plainTextEntry()
                    TextField(lang.t("参数(空格分隔)", "Args (space-separated)"), text: $mcpArgs, prompt: Text("-y @scope/server …")).plainTextEntry()
                    Button(lang.t("添加", "Add"), action: addMCP)
                        .disabled(mcpName.trimmed.isEmpty || mcpCommand.trimmed.isEmpty)
                }
                Text(lang.t("MCP 让 AI 能调用外部工具(数据库 / API / 浏览器等)。仅在「本机登录(Claude Code / Codex)」模式下生效;需本机能运行该命令。",
                            "MCP lets the AI call external tools (databases / APIs / browser…). Works in local-login (Claude Code / Codex) mode; the command must be runnable on this Mac."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(lang.t("外观", "Appearance")) {
                Picker(lang.t("主题", "Theme"), selection: $store.settings.theme) {
                    Text(lang.t("跟随系统", "System")).tag(ThemeMode.system)
                    Text(lang.t("浅色", "Light")).tag(ThemeMode.light)
                    Text(lang.t("深色", "Dark")).tag(ThemeMode.dark)
                }
                .pickerStyle(.segmented)
                Picker(lang.t("语言", "Language"), selection: $store.settings.language) {
                    Text("中文").tag(Lang.zh)
                    Text("English").tag(Lang.en)
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private func addMCP() {
        let name = mcpName.trimmed, cmd = mcpCommand.trimmed
        guard !name.isEmpty, !cmd.isEmpty, !store.settings.mcpServers.contains(where: { $0.id == name }) else { return }
        let args = mcpArgs.split(separator: " ").map(String.init)
        store.settings.mcpServers.append(MCPServer(id: name, command: cmd, args: args, enabled: true))
        mcpName = ""; mcpCommand = ""; mcpArgs = ""
    }

    private func addPreset(_ p: MCPPreset) {
        guard !store.settings.mcpServers.contains(where: { $0.id == p.id }) else { return }
        store.settings.mcpServers.append(p.server(projectDir: app.project.cwd))
    }
}
