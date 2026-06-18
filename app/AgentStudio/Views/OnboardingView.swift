import SwiftUI

/// First-launch guided tour. A friendly, paged overlay that explains the core flow to non-coders.
/// Shown once (gated by @AppStorage in RootView); reachable again from Settings.
struct OnboardingView: View {
    @Environment(\.lang) private var lang
    let onFinish: () -> Void

    @State private var step = 0

    private struct Page: Identifiable {
        let id = UUID()
        let icon: String
        let zhTitle: String, enTitle: String
        let zhBody: String, enBody: String
    }

    private var pages: [Page] {
        [
            Page(icon: "sparkles",
                 zhTitle: "欢迎使用 AgentStudio",
                 enTitle: "Welcome to AgentStudio",
                 zhBody: "你只要用大白话说出想做什么，AI 就会帮你规划、动手、自检，做出真正能用的网页或应用。完全不需要懂代码。",
                 enBody: "Just say what you want in plain words — the AI plans it, builds it, and checks its own work to make something that actually runs. No coding needed."),
            Page(icon: "cable.connector",
                 zhTitle: "先连接一个模型",
                 enTitle: "Connect a model first",
                 zhBody: "在每一栏右上角选择并点「连接」。可以复用本机的 Claude Code / Codex 登录，或填自己的 API Key。左右两栏各自独立连接。",
                 enBody: "Pick a model in each pane's top-right and click Connect — reuse your local Claude Code / Codex login, or paste an API key. The two panes connect independently."),
            Page(icon: "wand.and.stars",
                 zhTitle: "从「开始」起步",
                 enTitle: "Kick off from “Start”",
                 zhBody: "在「开始」页用一句话描述想法，或挑一个模板（个人主页、待办清单、小游戏…），AI 就会开始制作。",
                 enBody: "On the “Start” page, describe your idea in a line or pick a template (homepage, to-do list, mini game…) and the AI gets to work."),
            Page(icon: "rectangle.lefthalf.inset.filled",
                 zhTitle: "单独 与 协作",
                 enTitle: "Solo vs. Collaborate",
                 zhBody: "顶部可切换：单独 = 和一个助手对话、它独立完成全部；协作 = 左栏规划、右栏执行、自动审查与修订。",
                 enBody: "Toggle at the top: Solo = chat with one assistant that does everything itself; Collaborate = left plans, right executes, with automatic review and revision."),
            Page(icon: "play.circle",
                 zhTitle: "运行 · 改动 · 分享",
                 enTitle: "Run · Changes · Share",
                 zhBody: "「运行」一键跑起来并实时预览，出错会自动修复；「改动」能看每次改了什么、一键回滚；做好了用「分享」导出 ZIP。",
                 enBody: "“Run” launches it live and self-heals on errors; “Changes” shows every edit with one-click rollback; “Share” exports a ZIP when you're done."),
        ]
    }

    private var page: Page { pages[step] }
    private var isLast: Bool { step == pages.count - 1 }

    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
                .onTapGesture { } // swallow taps so the background isn't interactive

            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(Color.orange.opacity(0.14)).frame(width: 84, height: 84)
                    Image(systemName: page.icon).font(.system(size: 38, weight: .light)).foregroundStyle(.orange)
                }
                .padding(.top, 34).padding(.bottom, 18)

                Text(lang.t(page.zhTitle, page.enTitle))
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)

                Text(lang.t(page.zhBody, page.enBody))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10).padding(.horizontal, 30)
                    .frame(minHeight: 84, alignment: .top)

                // page dots
                HStack(spacing: 7) {
                    ForEach(pages.indices, id: \.self) { i in
                        Circle()
                            .fill(i == step ? Color.orange : Color.secondary.opacity(0.3))
                            .frame(width: 7, height: 7)
                    }
                }
                .padding(.vertical, 20)

                HStack {
                    if step > 0 {
                        Button(lang.t("上一步", "Back")) { withAnimation { step -= 1 } }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                    } else {
                        Button(lang.t("跳过", "Skip")) { onFinish() }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(isLast ? lang.t("开始使用", "Get started") : lang.t("下一步", "Next")) {
                        if isLast { onFinish() } else { withAnimation { step += 1 } }
                    }
                    .buttonStyle(.borderedProminent).tint(.orange).controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 28).padding(.bottom, 24)
            }
            .frame(width: 460)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.separator))
            .shadow(color: .black.opacity(0.25), radius: 30, y: 12)
        }
        .transition(.opacity)
    }
}
