import Foundation

/// Direct streaming client for the Anthropic Messages API.
/// POST https://api.anthropic.com/v1/messages  (x-api-key, anthropic-version: 2023-06-01, stream: true)
/// Parses SSE `content_block_delta` (text_delta) events into text chunks.
struct AnthropicClient: ProviderClient {
    func stream(_ req: ResolvedRequest) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let endpoint = URL(string: "\(req.baseURL)/v1/messages") else {
                        throw ProviderError.other("无效的 Base URL：\(req.baseURL)")
                    }
                    var request = URLRequest(url: endpoint)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue(req.apiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

                    var body: [String: Any] = [
                        "model": req.model,
                        "max_tokens": req.maxTokens,
                        "stream": true,
                        "messages": req.messages.map { ["role": $0.role.rawValue, "content": $0.content] },
                    ]
                    if let sys = req.systemPrompt, !sys.isEmpty { body["system"] = sys }
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await req.session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else { throw ProviderError.other("无响应") }
                    guard http.statusCode == 200 else {
                        throw classifyHTTP(http.statusCode, body: await drain(bytes))
                    }

                    var inputTokens = 0, outputTokens = 0
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard !payload.isEmpty,
                              let data = payload.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let type = obj["type"] as? String else { continue }

                        switch type {
                        case "message_start":
                            if let u = (obj["message"] as? [String: Any])?["usage"] as? [String: Any] {
                                inputTokens = (u["input_tokens"] as? Int) ?? inputTokens
                                outputTokens = (u["output_tokens"] as? Int) ?? outputTokens
                            }
                        case "content_block_delta":
                            if let delta = obj["delta"] as? [String: Any],
                               delta["type"] as? String == "text_delta",
                               let text = delta["text"] as? String {
                                continuation.yield(.delta(text))
                            }
                        case "message_delta":
                            if let u = obj["usage"] as? [String: Any], let o = u["output_tokens"] as? Int { outputTokens = o }
                        case "error":
                            let msg = (obj["error"] as? [String: Any])?["message"] as? String ?? "Anthropic 流式错误"
                            throw ProviderError.other(msg)
                        case "message_stop":
                            if inputTokens > 0 || outputTokens > 0 { continuation.yield(.usage(input: inputTokens, output: outputTokens)) }
                            continuation.finish(); return
                        default:
                            continue
                        }
                    }
                    if inputTokens > 0 || outputTokens > 0 { continuation.yield(.usage(input: inputTokens, output: outputTokens)) }
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

/// Read a bounded prefix of an error response body for diagnostics.
func drain(_ bytes: URLSession.AsyncBytes, limit: Int = 4000) async -> String {
    var data = Data()
    do {
        for try await b in bytes {
            data.append(b)
            if data.count >= limit { break }
        }
    } catch { /* ignore */ }
    return String(data: data, encoding: .utf8) ?? ""
}

/// 429 / 5xx are retryable (transient); everything else is a hard HTTP error.
func classifyHTTP(_ status: Int, body: String) -> ProviderError {
    if status == 429 || status >= 500 {
        return .transient("HTTP \(status)")
    }
    return .http(status: status, body: body)
}
