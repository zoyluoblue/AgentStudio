import SwiftUI

enum MainView: Hashable { case start, chat, changes, history, memory, run, share, settings }

/// Top-level shell: icon sidebar │ (top bar + active view).
struct RootView: View {
    @State private var app = AppController()
    @State private var view: MainView = .start
    @AppStorage("hasOnboarded") private var hasOnboarded = false

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                SidebarView(view: $view, onNewProject: { app.pickProject() })
                Divider()
                VStack(spacing: 0) {
                    TopBarView(app: app, onPick: { app.pickProject() })
                    Divider()
                    content
                }
            }

            if !hasOnboarded {
                OnboardingView(onFinish: { withAnimation { hasOnboarded = true } })
            }
        }
        .preferredColorScheme(colorScheme)
        .frame(minWidth: 1040, minHeight: 640)
        .tint(.orange)
        .environment(\.lang, app.settings.language) // bilingual: every view reads @Environment(\.lang)
        .task { await app.startup() } // model lists + login detection, after first paint
    }

    @ViewBuilder private var content: some View {
        switch view {
        case .start:
            StartView(app: app, onStarted: { view = .chat })
        case .chat:
            ChatView(app: app)
        case .changes:
            ChangesView(app: app)
        case .settings:
            SettingsView(app: app, store: app.settingsStore)
        case .history:
            HistoryView(app: app, onOpenChat: { view = .chat })
        case .memory:
            MemoryView(app: app)
        case .run:
            RunView(app: app)
        case .share:
            ShareView(app: app)
        }
    }

    private var colorScheme: ColorScheme? {
        switch app.settings.theme {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
}

#Preview {
    RootView().frame(width: 1280, height: 820)
}
