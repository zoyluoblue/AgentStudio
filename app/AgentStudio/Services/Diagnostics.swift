import Foundation

/// v1.1 — connection self-check. One result item per check, with a plain-language detail and an
/// actionable fix hint. Built on existing pieces (validateKey / AgentAuth / PathResolver / proxy).
struct DiagnosticItem: Identifiable, Sendable {
    enum Status: String, Sendable { case ok, warn, fail, info }
    let id = UUID()
    var status: Status
    var title: String
    var detail: String
    var fix: String?
}

enum Diagnostics {
    /// Quick reachability probe of a base URL — any HTTP response counts as reachable (only a
    /// network failure throws). Bounded by a short timeout.
    static func reachable(_ urlString: String, session: URLSession) async -> Bool {
        guard let url = URL(string: urlString) else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        req.timeoutInterval = 6
        do { _ = try await session.data(for: req); return true } catch { return false }
    }

    /// The login-shell SOCKS proxy, if any — the CLIs' fetch can't use SOCKS, a common cause of
    /// "socket closed" / failures. Returns the offending value for the hint.
    static func socksProxyInEnv() -> String? {
        for k in ["ALL_PROXY", "all_proxy", "HTTPS_PROXY", "https_proxy"] {
            if let v = PathResolver.loginEnv[k], v.lowercased().hasPrefix("socks") { return v }
        }
        return nil
    }
}
