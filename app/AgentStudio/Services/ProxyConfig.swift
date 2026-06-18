import Foundation

/// Builds a URLSession that honors the user's proxy preference + lane scope, mirroring
/// the env-var proxy logic the Electron app applied to its child processes (settings.ts).
///   - .none / out-of-scope lane  → proxy explicitly disabled
///   - .custom (in scope)         → route through proxyUrl (host:port)
///   - .system (in scope)         → inherit the OS network proxy (URLSession default)
/// DeepSeek passes `direct: true` (reachable directly in CN, bypasses the proxy).
enum ProxyConfig {
    static func session(settings: AppSettings, lane: Lane, direct: Bool = false) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 600
        config.waitsForConnectivity = false

        let inScope = settings.proxyScope == .both || settings.proxyScope.rawValue == lane.rawValue
        let usesProxy = !direct && settings.proxyMode != .none && inScope

        if !usesProxy {
            config.connectionProxyDictionary = [:] // disable system/inherited proxy
        } else if settings.proxyMode == .custom, let (host, port) = parse(settings.proxyUrl) {
            config.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable as String: 1,
                kCFNetworkProxiesHTTPProxy as String: host,
                kCFNetworkProxiesHTTPPort as String: port,
                "HTTPSEnable": 1,
                "HTTPSProxy": host,
                "HTTPSPort": port,
            ]
        }
        // .system in scope → leave connectionProxyDictionary nil so URLSession uses OS settings.
        return URLSession(configuration: config)
    }

    /// The proxy host:port a lane will actually use (for error hints), or nil.
    static func effective(settings: AppSettings, lane: Lane) -> String? {
        let inScope = settings.proxyScope == .both || settings.proxyScope.rawValue == lane.rawValue
        guard settings.proxyMode != .none, inScope else { return nil }
        guard settings.proxyMode == .custom else { return nil } // system proxy host isn't introspected here
        let u = settings.proxyUrl.trimmed
        guard !u.isEmpty else { return nil }
        return u.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// Parse "http://127.0.0.1:7890" (or "127.0.0.1:7890") into (host, port).
    private static func parse(_ raw: String) -> (String, Int)? {
        var s = raw.trimmed
        guard !s.isEmpty else { return nil }
        s = s.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let parts = s.split(separator: ":")
        guard parts.count == 2, let port = Int(parts[1]) else { return nil }
        return (String(parts[0]), port)
    }
}
