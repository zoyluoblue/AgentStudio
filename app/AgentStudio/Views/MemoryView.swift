import SwiftUI

/// View + edit long-term memory: curated (user-written) and learned (auto-extracted),
/// at global or project scope. Memory is injected into every model turn.
struct MemoryView: View {
    @Bindable var app: AppController
    @Environment(\.lang) private var lang

    @State private var scope: MemoryScope = .global
    @State private var curated = ""
    @State private var learned = ""
    @State private var consolidating = false

    private var hasProject: Bool { app.project.cwd != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Picker(lang.t("范围", "Scope"), selection: $scope) {
                    Text(lang.t("全局（所有项目）", "Global (all projects)")).tag(MemoryScope.global)
                    Text(hasProject ? lang.t("本项目", "This project") : lang.t("本项目（未选择）", "This project (none)")).tag(MemoryScope.project)
                }
                .pickerStyle(.segmented)
                .frame(width: 320)
                .onChange(of: scope) { _, _ in load() }
                Spacer()
            }
            .padding(12)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    section(
                        title: lang.t("手动记忆", "Manual memory"),
                        subtitle: lang.t("你写的、或用「记住 …」存下的内容。", "Things you wrote, or saved via “remember …”."),
                        text: $curated,
                        onSave: {
                            MemoryStore.set(scope: scope, kind: .curated, content: curated, cwd: app.project.cwd)
                        }
                    )

                    section(
                        title: lang.t("自动记忆", "Auto memory"),
                        subtitle: lang.t("从对话里自动提炼的要点。", "Points auto-extracted from conversations."),
                        text: $learned,
                        onSave: {
                            MemoryStore.set(scope: scope, kind: .learned, content: learned, cwd: app.project.cwd)
                        },
                        extra: AnyView(
                            Button {
                                consolidating = true
                                Task {
                                    learned = await app.consolidate(scope: scope)
                                    consolidating = false
                                }
                            } label: {
                                if consolidating { ProgressView().controlSize(.small) }
                                else { Label(lang.t("整理去重", "Tidy & dedupe"), systemImage: "wand.and.stars") }
                            }
                            .disabled(consolidating || learned.trimmed.isEmpty)
                        )
                    )
                }
                .padding(14)
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
        .task { load() }
        .onChange(of: app.project.cwd) { _, _ in load() }
    }

    private func load() {
        curated = MemoryStore.get(scope: scope, kind: .curated, cwd: app.project.cwd)
        learned = MemoryStore.get(scope: scope, kind: .learned, cwd: app.project.cwd)
    }

    private func section(title: String, subtitle: String, text: Binding<String>, onSave: @escaping () -> Void, extra: AnyView? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let extra { extra }
                Button(lang.t("保存", "Save"), action: onSave).buttonStyle(.bordered)
            }
            TextEditor(text: text)
                .font(.system(.callout, design: .monospaced))
                .frame(minHeight: 160)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
        }
    }
}
