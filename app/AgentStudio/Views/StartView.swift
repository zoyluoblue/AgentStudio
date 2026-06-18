import SwiftUI

/// R5 — guided start. The friendly front door for non-coders: describe what you want in plain
/// language, or pick a template. Either path ensures a project folder, lays down a scaffold, and
/// kicks off the plan→execute→review build.
struct StartView: View {
    @Bindable var app: AppController
    @Environment(\.lang) private var lang
    let onStarted: () -> Void

    @State private var goal = ""

    private let columns = [GridItem(.adaptive(minimum: 240), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                freeform
                templates
            }
            .padding(28)
            .frame(maxWidth: 880, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    // MARK: - hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(.orange)
                Text(lang.t("你想做点什么？", "What do you want to make?")).font(.largeTitle.weight(.semibold))
            }
            Text(lang.t("用大白话描述你的想法，或从下面的模板开始。AgentStudio 会规划、动手、自检，做出来给你看。",
                        "Describe your idea in plain words, or start from a template. AgentStudio will plan, build, and self-check it for you."))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - free-form goal

    private var freeform: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField(lang.t("例如：做一个记录每天喝水量的小网页",
                                 "e.g. a little web app to track how much water I drink each day"),
                          text: $goal, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .padding(12)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 11))
                    .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(.separator))
                    .onSubmit(startFreeform)

                Button(action: startFreeform) {
                    Label(lang.t("开始制作", "Start building"), systemImage: "arrow.up.circle.fill")
                        .padding(.vertical, 6).padding(.horizontal, 4)
                }
                .buttonStyle(.borderedProminent).tint(.orange)
                .disabled(goal.trimmed.isEmpty)
            }
            if app.project.cwd == nil {
                Label(lang.t("点击后会先让你选择一个项目文件夹。", "You'll pick a project folder first."),
                      systemImage: "folder")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - templates

    private var templates: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(lang.t("或者，从模板开始", "Or start from a template")).font(.headline)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(TemplateLibrary.all) { card($0) }
            }
        }
    }

    private func card(_ t: AppTemplate) -> some View {
        Button { start(template: t) } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: t.icon)
                    .font(.title2).foregroundStyle(.orange)
                    .frame(width: 34, height: 34)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 3) {
                    Text(t.title(lang)).font(.callout.weight(.semibold)).foregroundStyle(.primary)
                    Text(t.desc(lang)).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - actions

    private func startFreeform() {
        let g = goal.trimmed
        guard !g.isEmpty else { return }
        if app.startGuided(goal: g, files: []) { goal = ""; onStarted() }
    }

    private func start(template t: AppTemplate) {
        if app.startGuided(goal: t.goal(lang), files: t.files(lang)) { onStarted() }
    }
}
