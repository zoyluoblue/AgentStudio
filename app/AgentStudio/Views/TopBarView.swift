import SwiftUI

/// Project selector + solo/collab mode toggle + language switch.
struct TopBarView: View {
    @Bindable var app: AppController
    let onPick: () -> Void
    @Environment(\.lang) private var lang
    @State private var showCost = false

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPick) {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                    Text(app.project.name ?? lang.t("选择项目文件夹", "Choose project folder"))
                        .lineLimit(1)
                }
            }
            .buttonStyle(.borderless)
            .help(app.project.cwd ?? lang.t("尚未选择项目", "No project selected"))

            Spacer()

            costChip



            Picker("", selection: Binding(get: { app.mode }, set: { app.setMode($0) })) {
                Text(lang.t("单独", "Solo")).tag(Mode.solo)
                Text(lang.t("协作", "Collab")).tag(Mode.collab)
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
            .help(lang.t("单独：分别和两个智能体对话；协作：左侧规划、右侧执行、自动审查",
                         "Solo: chat with each agent separately. Collab: left plans, right executes, auto-reviews."))

            Button(action: { app.toggleLanguage() }) {
                Text(lang.switchLabel).frame(minWidth: 24)
            }
            .buttonStyle(.bordered)
            .help(lang.t("切换到 English", "Switch to 中文"))
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - cost chip (R4)

    private var costChip: some View {
        Button { showCost.toggle() } label: {
            HStack(spacing: 4) {
                Image(systemName: "dollarsign.circle").font(.caption)
                Text("≈$\(app.money(app.costMonth))").font(.caption.monospacedDigit())
            }
            .foregroundStyle(chipColor)
        }
        .buttonStyle(.borderless)
        .help(lang.t("本月预计花费（仅 API Key 用量）", "Estimated spend this month (API-key usage only)"))
        .popover(isPresented: $showCost, arrowEdge: .bottom) { costPopover.frame(width: 280) }
    }

    private var chipColor: Color {
        if app.overBudget { return .red }
        if app.budgetFraction >= 0.8 { return .orange }
        return .secondary
    }

    private var costPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(lang.t("用量与花费（估算）", "Usage & spend (estimated)")).font(.headline)

            row(lang.t("今天", "Today"), "≈$\(app.money(app.costToday))")
            row(lang.t("本月", "This month"), "≈$\(app.money(app.costMonth))")
            row(lang.t("累计", "All time"), "≈$\(app.money(app.costTotal))")
            row(lang.t("累计 tokens", "Total tokens"), tokenText(app.tokensTotal))

            if app.monthlyBudget > 0 {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(lang.t("本月预算", "Monthly budget")).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("$\(app.money(app.monthlyBudget))").font(.caption.monospacedDigit())
                    }
                    ProgressView(value: app.budgetFraction)
                        .tint(app.overBudget ? .red : (app.budgetFraction >= 0.8 ? .orange : .green))
                    if app.overBudget {
                        Text(lang.t("已达上限，新对话已暂停。可在设置里调整。",
                                    "Limit reached — new turns paused. Adjust it in Settings."))
                            .font(.caption2).foregroundStyle(.red)
                    }
                }
            }

            Divider()
            Text(lang.t("数字为按公开价估算，实际以服务商账单为准。使用本地 CLI 登录时不计费。",
                        "Figures are estimates at list prices; your provider bill is authoritative. Local CLI login isn't billed here."))
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(12)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value).monospacedDigit() }
            .font(.callout)
    }

    private func tokenText(_ n: Int) -> String {
        n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1_000_000)
            : n >= 1_000 ? String(format: "%.1fK", Double(n) / 1_000) : "\(n)"
    }
}
