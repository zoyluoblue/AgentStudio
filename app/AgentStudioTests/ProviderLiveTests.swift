import XCTest
@testable import AgentStudio

/// Live end-to-end tests against the real provider endpoints (via the derouter proxy + DeepSeek).
/// Credentials come from `tools/test.env` (gitignored); without them these `XCTSkip`.
final class ProviderLiveTests: XCTestCase {

    private func settings(backend: Backend, key: String, base: String?) -> AppSettings {
        var s = AppSettings.defaults
        s.proxyMode = .none
        s.masterBackend = backend
        s.connectMethod[.master] = .key
        s.apiKeys[.master] = key
        if let base {
            s.useDefaultBaseURL[.master] = false
            s.baseURLs[.master] = base
        }
        return s
    }

    private func ping(backend: Backend, model: String?, settings s: AppSettings) async -> LLMEngine.Completion {
        let req = ChatRequest(backend: backend, lane: .master, model: model, systemPrompt: nil,
                              messages: [LLMMessage(role: .user, content: "Reply with just the single word: pong")],
                              maxTokens: 64)
        return await LLMEngine.complete(req, settings: s)
    }

    /// Assert a live call worked — but a rejected key (401/403) is a credential issue, not a code
    /// bug, so skip with a clear note instead of failing the suite.
    private func assertLive(_ r: LLMEngine.Completion, _ who: String) throws {
        if !r.ok, let e = r.error, e.contains("401") || e.contains("403") || e.lowercased().contains("authentication") {
            throw XCTSkip("\(who): key rejected by the provider (update tools/test.env): \(e)")
        }
        XCTAssertTrue(r.ok, "\(who) failed: \(r.error ?? "?")")
        XCTAssertFalse(r.text.isEmpty)
    }

    func testClaudeViaDerouter() async throws {
        guard let key = TestConfig.value("AS_TEST_DEROUTER_KEY"), let base = TestConfig.value("AS_TEST_CLAUDE_BASE") else {
            throw XCTSkip("AS_TEST_DEROUTER_KEY / AS_TEST_CLAUDE_BASE not set")
        }
        let r = await ping(backend: .claude, model: nil, settings: settings(backend: .claude, key: key, base: base))
        print("CLAUDE →", r.ok ? r.text : (r.error ?? "?"))
        try assertLive(r, "claude")
    }

    func testOpenAIViaDerouter() async throws {
        guard let key = TestConfig.value("AS_TEST_DEROUTER_KEY"), let base = TestConfig.value("AS_TEST_OPENAI_BASE") else {
            throw XCTSkip("AS_TEST_DEROUTER_KEY / AS_TEST_OPENAI_BASE not set")
        }
        let r = await ping(backend: .codex, model: "gpt-5.4", settings: settings(backend: .codex, key: key, base: base))
        print("OPENAI →", r.ok ? r.text : (r.error ?? "?"))
        try assertLive(r, "openai")
    }

    func testDeepSeekLive() async throws {
        guard let key = TestConfig.value("AS_TEST_DEEPSEEK_KEY") else { throw XCTSkip("AS_TEST_DEEPSEEK_KEY not set") }
        let r = await ping(backend: .deepseek, model: "deepseek-chat", settings: settings(backend: .deepseek, key: key, base: nil))
        print("DEEPSEEK →", r.ok ? r.text : (r.error ?? "?"))
        try assertLive(r, "deepseek")
    }

    // MARK: - A2: tool-use agent loop (real read/write/edit against a temp project)

    private func tempProject() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("asagent-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func assertAgent(_ r: AgentEngine.Result, _ who: String) throws {
        if !r.ok, let e = r.error, e.contains("401") || e.contains("403") || e.lowercased().contains("authentication") {
            throw XCTSkip("\(who): key rejected (update tools/test.env): \(e)")
        }
        XCTAssertTrue(r.ok, "\(who) agent loop failed: \(r.error ?? "?")")
    }

    /// Recursively find the first file with `name` under `dir` (model may namespace into a subfolder).
    private func findFile(_ name: String, under dir: URL) -> URL? {
        guard let en = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else { return nil }
        for case let u as URL in en where u.lastPathComponent == name { return u }
        return nil
    }

    /// Claude must actually call write_file to create a real file on disk.
    func testAgentLoopClaudeCreatesFile() async throws {
        guard let key = TestConfig.value("AS_TEST_DEROUTER_KEY"), let base = TestConfig.value("AS_TEST_CLAUDE_BASE") else {
            throw XCTSkip("AS_TEST_DEROUTER_KEY / AS_TEST_CLAUDE_BASE not set")
        }
        let dir = tempProject(); defer { try? FileManager.default.removeItem(at: dir) }
        let res = await AgentEngine.run(lane: .master, backend: .claude, model: "claude-opus-4-8",
                                        system: Prompts.agentExecutor(.en),
                                        prompt: "Create a file named note.txt whose entire content is exactly: AgentStudio works",
                                        cwd: dir.path, settings: settings(backend: .claude, key: key, base: base),
                                        onActivity: { _ in })
        print("AGENT/claude →", res.ok ? "\(res.changed) :: \(res.text.prefix(80))" : (res.error ?? "?"))
        try assertAgent(res, "claude")
        // The model may namespace the file into a subfolder — accept it anywhere with the right content.
        let made = findFile("note.txt", under: dir)
        let content = made.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        XCTAssertTrue(content.contains("AgentStudio works"), "expected a note.txt created; changed=\(res.changed)")
        XCTAssertFalse(res.changed.isEmpty, "changed list should record the write: \(res.changed)")
    }

    /// Claude must read an existing file and edit it in place (exercises read_file + edit_file).
    func testAgentLoopClaudeEditsFile() async throws {
        guard let key = TestConfig.value("AS_TEST_DEROUTER_KEY"), let base = TestConfig.value("AS_TEST_CLAUDE_BASE") else {
            throw XCTSkip("AS_TEST_DEROUTER_KEY / AS_TEST_CLAUDE_BASE not set")
        }
        let dir = tempProject(); defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("greeting.txt")
        try "Hello, world!".write(to: file, atomically: true, encoding: .utf8)
        let res = await AgentEngine.run(lane: .master, backend: .claude, model: "claude-opus-4-8",
                                        system: Prompts.agentExecutor(.en),
                                        prompt: "In greeting.txt, change the word 'world' to 'AgentStudio'. Read it first, then edit it.",
                                        cwd: dir.path, settings: settings(backend: .claude, key: key, base: base),
                                        onActivity: { _ in })
        print("AGENT/claude-edit →", res.ok ? "\(res.changed)" : (res.error ?? "?"))
        try assertAgent(res, "claude-edit")
        let content = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        XCTAssertTrue(content.contains("AgentStudio"), "expected the edit applied; got: \(content)")
    }

    // MARK: - Plan B: Claude Agent SDK bridge (Node sidecar)

    private func bridgeScript() -> String {
        // app/AgentStudioTests/ProviderLiveTests.swift → app/tools/agent-bridge/bridge.mjs
        let appDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return appDir.appendingPathComponent("tools/agent-bridge/bridge.mjs").path
    }

    /// The Agent SDK bridge must drive a real Claude agent run (through our Anthropic-compatible
    /// endpoint) and create a file at the real cwd.
    func testAgentSDKClaudeCreatesFile() async throws {
        guard let key = TestConfig.value("AS_TEST_DEROUTER_KEY"), let base = TestConfig.value("AS_TEST_CLAUDE_BASE") else {
            throw XCTSkip("AS_TEST_DEROUTER_KEY / AS_TEST_CLAUDE_BASE not set")
        }
        guard let node = PathResolver.resolve("node") else { throw XCTSkip("node not found on PATH") }
        let script = bridgeScript()
        guard FileManager.default.fileExists(atPath: script) else { throw XCTSkip("bridge.mjs missing at \(script)") }
        guard AgentSDKClient.isInstalled(script: script) else { throw XCTSkip("agent-bridge deps not installed (npm install in tools/agent-bridge)") }

        let dir = tempProject(); defer { try? FileManager.default.removeItem(at: dir) }
        let res = await AgentSDKClient.run(
            node: node, script: script, lane: .master, model: "claude-opus-4-8",
            system: "You are AgentStudio's executor. Implement the request by editing files, then say what you did in one sentence.",
            prompt: "Create a file named note.txt whose entire content is exactly: SDK works",
            cwd: dir.path, settings: settings(backend: .claude, key: key, base: base),
            onText: { _ in }, onActivity: { _ in })
        print("AGENTSDK/claude →", res.ok ? "\(res.changed) :: $\(res.costUSD) in=\(res.input) out=\(res.output)" : (res.error ?? "?"))
        if !res.ok, let e = res.error, e.contains("401") || e.contains("403") || e.lowercased().contains("authentic") {
            throw XCTSkip("claude(sdk): key rejected: \(e)")
        }
        XCTAssertTrue(res.ok, "agent sdk bridge failed: \(res.error ?? "?")")
        let made = findFile("note.txt", under: dir)
        let content = made.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        XCTAssertTrue(content.contains("SDK works"), "expected note.txt at real cwd; changed=\(res.changed)")
        XCTAssertFalse(res.changed.isEmpty, "changed should record the write: \(res.changed)")
        XCTAssertGreaterThan(res.output, 0, "should report output tokens")
    }

    /// The OpenAI tool_calls path must also create a real file.
    func testAgentLoopOpenAICreatesFile() async throws {
        guard let key = TestConfig.value("AS_TEST_DEROUTER_KEY"), let base = TestConfig.value("AS_TEST_OPENAI_BASE") else {
            throw XCTSkip("AS_TEST_DEROUTER_KEY / AS_TEST_OPENAI_BASE not set")
        }
        let dir = tempProject(); defer { try? FileManager.default.removeItem(at: dir) }
        let res = await AgentEngine.run(lane: .master, backend: .codex, model: "gpt-5.4",
                                        system: Prompts.agentExecutor(.en),
                                        prompt: "Create a file named note.txt whose entire content is exactly: AgentStudio works",
                                        cwd: dir.path, settings: settings(backend: .codex, key: key, base: base),
                                        onActivity: { _ in })
        print("AGENT/openai →", res.ok ? "\(res.changed) :: \(res.text.prefix(80))" : (res.error ?? "?"))
        try assertAgent(res, "openai")
        let content = (try? String(contentsOf: dir.appendingPathComponent("note.txt"), encoding: .utf8)) ?? ""
        XCTAssertTrue(content.contains("AgentStudio works"), "expected note.txt created; got: \(content)")
    }
}
