import Foundation

/// The engine: resolves a ChatRequest against settings (key, model, proxy), picks the right
/// provider client, and wraps the stream with transient-error retry + exponential backoff —
/// mirroring the claudeDriver.ts retry behavior, but for direct HTTP streaming.
enum LLMEngine {
    static let maxTries = 5

    /// Stream a completion. Retries transient failures that occur *before* any text is produced.
    static func stream(_ req: ChatRequest, settings: AppSettings) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let backend = req.backend
                let key = settings.apiKey(for: req.lane)
                guard !key.isEmpty else {
                    continuation.finish(throwing: ProviderError.missingKey(backend)); return
                }
                let model = (req.model?.nonEmpty) ?? LLMModels.defaultModel(backend)
                let session = ProxyConfig.session(settings: settings, lane: req.lane, direct: backend == .deepseek)
                let client: ProviderClient = backend == .claude ? AnthropicClient() : OpenAICompatibleClient(kind: backend)
                let resolved = ResolvedRequest(
                    model: model, systemPrompt: req.systemPrompt, messages: req.messages,
                    maxTokens: req.maxTokens, apiKey: key,
                    baseURL: settings.effectiveBaseURL(for: req.lane), session: session
                )

                var attempt = 0
                while true {
                    if Task.isCancelled { continuation.finish(throwing: ProviderError.cancelled); return }
                    var produced = false
                    do {
                        for try await ev in client.stream(resolved) {
                            if case .delta = ev { produced = true }
                            continuation.yield(ev)
                        }
                        continuation.finish(); return
                    } catch {
                        // Only retry transient, pre-output failures (the proxy-drop class).
                        let next = attempt + 1
                        if produced || !isTransient(error) || next >= maxTries {
                            continuation.finish(throwing: finalError(error, settings: settings, lane: req.lane)); return
                        }
                        attempt = next
                        continuation.yield(.status("重连中（第 \(attempt) 次重试）"))
                        let backoff = min(0.8 * pow(2, Double(attempt - 1)), 8.0) + Double.random(in: 0..<0.4)
                        try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    struct Completion: Sendable { var ok: Bool; var text: String; var error: String?; var input = 0; var output = 0 }

    /// Drain a stream to a full string (non-incremental callers / memory extraction).
    static func complete(_ req: ChatRequest, settings: AppSettings, onDelta: (@Sendable (String) -> Void)? = nil) async -> Completion {
        var text = ""
        var input = 0, output = 0
        do {
            for try await ev in stream(req, settings: settings) {
                switch ev {
                case .delta(let d): text += d; onDelta?(text)
                case .usage(let i, let o): input = i; output = o
                case .status: break
                }
            }
            return text.isEmpty ? Completion(ok: false, text: "", error: ProviderError.empty.errorDescription)
                                 : Completion(ok: true, text: text, error: nil, input: input, output: output)
        } catch {
            return Completion(ok: false, text: text, error: (error as? LocalizedError)?.errorDescription ?? "\(error)", input: input, output: output)
        }
    }

    // MARK: - retry classification

    private static func isTransient(_ error: Error) -> Bool {
        if case ProviderError.transient = error { return true }
        if let u = error as? URLError {
            switch u.code {
            case .timedOut, .networkConnectionLost, .cannotConnectToHost, .notConnectedToInternet,
                 .dnsLookupFailed, .cannotFindHost, .resourceUnavailable, .secureConnectionFailed:
                return true
            default: break
            }
        }
        let m = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        return m.range(of: "socket|closed|reset|timed? ?out|network|connection", options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func finalError(_ error: Error, settings: AppSettings, lane: Lane) -> Error {
        if case ProviderError.cancelled = error { return error }
        guard isTransient(error) else { return error }
        let proxy = ProxyConfig.effective(settings: settings, lane: lane)
        let hint = proxy.map {
            "网络连接被反复中断 —— 多半是本地代理（\($0)）此刻不稳定。已自动重试 \(maxTries) 次仍失败，建议切换代理节点/模式后再发一次。"
        } ?? "网络连接被反复中断，已重试 \(maxTries) 次仍失败，请稍后再试。"
        return ProviderError.other(hint)
    }

    /// Outcome of an API-key check.
    enum KeyCheck: Sendable {
        case ok          // 2xx — key + endpoint confirmed
        case authFailed  // 401/403 — key rejected
        case unverified  // endpoint didn't answer /models (custom proxy, 404, 5xx, network) — can't disprove the key
    }

    /// Validate an API key by hitting the lane backend's `/models` endpoint — cheap, no token cost.
    /// Distinguishes a rejected key from an endpoint that simply doesn't expose /models (proxies).
    static func validateKey(lane: Lane, key: String, settings: AppSettings) async -> KeyCheck {
        guard !key.isEmpty else { return .authFailed }
        let backend = settings.backend(for: lane)
        let session = ProxyConfig.session(settings: settings, lane: lane, direct: backend == .deepseek)
        let headers: [String: String]
        switch backend {
        case .claude: headers = ["x-api-key": key, "anthropic-version": "2023-06-01"]
        case .codex, .deepseek: headers = ["Authorization": "Bearer \(key)"]
        }
        guard let url = URL(string: modelsURL(lane, settings: settings)) else { return .unverified }
        var req = URLRequest(url: url)
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        do {
            let (_, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if (200...299).contains(code) { return .ok }
            if code == 401 || code == 403 { return .authFailed }
            return .unverified
        } catch {
            return .unverified
        }
    }

    // MARK: - model lists (mirrors main/index.ts listModels)

    static func listModels(lane: Lane, settings: AppSettings) async -> [ModelOption] {
        let backend = settings.backend(for: lane)
        let key = settings.apiKey(for: lane)
        let session = ProxyConfig.session(settings: settings, lane: lane, direct: backend == .deepseek)

        let url = modelsURL(lane, settings: settings)
        switch backend {
        case .deepseek:
            guard !key.isEmpty else { return LLMModels.deepseekFallback }
            let ids = await fetchModelIds(url, headers: ["Authorization": "Bearer \(key)"], session: session)
            return ids.isEmpty ? LLMModels.deepseekFallback : ids.sorted().map { ModelOption(id: $0, label: $0) }

        case .claude:
            guard !key.isEmpty else { return LLMModels.claude }
            let ids = await fetchModelIds(url, headers: ["x-api-key": key, "anthropic-version": "2023-06-01"], session: session)
            let known = Set(LLMModels.claude.map(\.id))
            let extra = ids.filter { !known.contains($0) }.sorted().reversed().map { ModelOption(id: $0, label: $0) }
            return LLMModels.claude + extra

        case .codex:
            guard !key.isEmpty else { return [] } // picker falls back to a free-text field
            let ids = await fetchModelIds(url, headers: ["Authorization": "Bearer \(key)"], session: session)
            let chat = ids.filter { $0.range(of: "^(gpt-|o\\d|chatgpt|codex)", options: .regularExpression) != nil }
            return (chat.isEmpty ? ids : chat).sorted().reversed().map { ModelOption(id: $0, label: $0) }
        }
    }

    /// The `/models` endpoint for a lane, honoring its backend + (default or custom) base URL.
    private static func modelsURL(_ lane: Lane, settings: AppSettings) -> String {
        let base = settings.effectiveBaseURL(for: lane)
        return settings.backend(for: lane) == .claude ? "\(base)/v1/models" : "\(base)/models"
    }

    /// GET an OpenAI-compatible `/models` endpoint → list of ids; [] on any failure.
    private static func fetchModelIds(_ urlString: String, headers: [String: String], session: URLSession) async -> [String] {
        guard let url = URL(string: urlString) else { return [] }
        var req = URLRequest(url: url)
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        do {
            let (data, resp) = try await session.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let arr = obj["data"] as? [[String: Any]] else { return [] }
            return arr.compactMap { $0["id"] as? String }
        } catch {
            return []
        }
    }
}
