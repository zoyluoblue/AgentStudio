import Foundation

/// Streaming client for OpenAI-compatible Chat Completions APIs — used for both the
/// `codex` lane (OpenAI) and `deepseek`. Same wire format: POST /chat/completions with
/// `stream: true`, SSE `data:` lines carrying `choices[0].delta.content`, terminated by
/// `data: [DONE]`. The system prompt is sent as a leading system-role message.
struct OpenAICompatibleClient: ProviderClient {
    let kind: Backend // .codex (OpenAI) or .deepseek

    func stream(_ req: ResolvedRequest) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let endpoint = URL(string: "\(req.baseURL)/chat/completions") else {
                        throw ProviderError.other("无效的 Base URL：\(req.baseURL)")
                    }
                    var request = URLRequest(url: endpoint)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("Bearer \(req.apiKey)", forHTTPHeaderField: "Authorization")

                    var msgs: [[String: String]] = []
                    if let sys = req.systemPrompt, !sys.isEmpty { msgs.append(["role": "system", "content": sys]) }
                    msgs.append(contentsOf: req.messages.map { ["role": $0.role.rawValue, "content": $0.content] })
                    let body: [String: Any] = [
                        "model": req.model,
                        "messages": msgs,
                        "stream": true,
                        // Ask for a final usage chunk (token counts) so we can meter cost.
                        "stream_options": ["include_usage": true],
                        // Otherwise DeepSeek defaults to 4096 and truncates big B1 whole-file output.
                        "max_tokens": kind == .deepseek ? min(req.maxTokens, 8192) : req.maxTokens,
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await req.session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else { throw ProviderError.other("无响应") }
                    guard http.statusCode == 200 else {
                        throw classifyHTTP(http.statusCode, body: await drain(bytes))
                    }

                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload.isEmpty { continue }
                        if payload == "[DONE]" { continuation.finish(); return }
                        guard let data = payload.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                        if let err = obj["error"] as? [String: Any] {
                            throw ProviderError.other(err["message"] as? String ?? "\(kind.displayName) 流式错误")
                        }
                        if let choices = obj["choices"] as? [[String: Any]],
                           let delta = choices.first?["delta"] as? [String: Any],
                           let text = delta["content"] as? String, !text.isEmpty {
                            continuation.yield(.delta(text))
                        }
                        // Final usage chunk (choices empty): prompt_tokens / completion_tokens.
                        if let u = obj["usage"] as? [String: Any] {
                            let i = (u["prompt_tokens"] as? Int) ?? 0
                            let o = (u["completion_tokens"] as? Int) ?? 0
                            if i > 0 || o > 0 { continuation.yield(.usage(input: i, output: o)) }
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: ProviderError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
