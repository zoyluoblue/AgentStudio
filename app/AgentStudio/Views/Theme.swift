import SwiftUI

/// Lightweight semantic palette. Leans on native macOS materials/semantic colors so the
/// app respects light/dark automatically, with a couple of brand accents per backend.
enum Theme {
    static let gutter: CGFloat = 12
    static let radius: CGFloat = 12

    static func accent(_ backend: Backend) -> Color {
        switch backend {
        case .claude: return Color(red: 0.85, green: 0.46, blue: 0.27)   // Claude terracotta
        case .codex: return Color(red: 0.10, green: 0.10, blue: 0.12)    // Codex graphite
        case .deepseek: return Color(red: 0.30, green: 0.42, blue: 0.996) // DeepSeek blue
        }
    }

    static func icon(_ backend: Backend) -> String {
        switch backend {
        case .claude: return "sparkles"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .deepseek: return "brain"
        }
    }

    static func roleColor(_ role: Role) -> Color {
        switch role {
        case .user: return .accentColor
        case .claude: return accent(.claude)
        case .codex: return .primary
        case .system: return .secondary
        }
    }
}

/// Render text as lightweight markdown, tolerating partial/streaming input.
func renderMarkdown(_ text: String) -> AttributedString {
    (try? AttributedString(markdown: text, options: .init(
        interpretedSyntax: .inlineOnlyPreservingWhitespace,
        failurePolicy: .returnPartiallyParsedIfPossible
    ))) ?? AttributedString(text)
}
