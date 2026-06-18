import XCTest
@testable import AgentStudio

/// Pure-logic tests — deterministic, no network/keys. The bulk of AgentStudio's value lives here.
final class LogicTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("astest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    private func write(_ rel: String, _ content: String) throws {
        let u = tmp.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: u, atomically: true, encoding: .utf8)
    }
    private func read(_ rel: String) -> String? { try? String(contentsOf: tmp.appendingPathComponent(rel), encoding: .utf8) }

    // MARK: whole-file write + path-escape guard
    func testApplyFilesWritesAndBlocksEscape() {
        let text = "<<<FILE: index.html>>>\n<h1>hi</h1>\n<<<END FILE>>>\n<<<FILE: ../evil.txt>>>\nnope\n<<<END FILE>>>"
        let p = ProjectFiles.parseFileBlocks(text)
        XCTAssertEqual(p.files.count, 2)
        let written = ProjectFiles.applyFiles(cwd: tmp.path, files: p.files)
        XCTAssertEqual(written, ["index.html"])                       // escape was refused
        XCTAssertEqual(read("index.html"), "<h1>hi</h1>")
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmp.deletingLastPathComponent().appendingPathComponent("evil.txt").path))
    }

    // MARK: B2 search/replace edits
    func testApplyEditsReplacesAndReportsMisses() throws {
        try write("a.js", "let x = 1;\nconsole.log(x);\n")
        let text = """
        <<<EDIT: a.js>>>
        <<<SEARCH>>>
        let x = 1;
        <<<REPLACE>>>
        let x = 42;
        <<<END EDIT>>>
        <<<EDIT: a.js>>>
        <<<SEARCH>>>
        this text is not in the file
        <<<REPLACE>>>
        whatever
        <<<END EDIT>>>
        """
        let edits = ProjectFiles.parseEdits(text)
        XCTAssertEqual(edits.count, 2)
        let r = ProjectFiles.applyEdits(cwd: tmp.path, edits: edits)
        XCTAssertEqual(r.applied, ["a.js"])
        XCTAssertEqual(r.failed, ["a.js"])                            // the non-matching edit is reported
        XCTAssertEqual(read("a.js"), "let x = 42;\nconsole.log(x);\n")
    }

    /// Models often pad the SEARCH snippet with a stray leading/trailing newline (assuming the file
    /// ends in one). The trimmed-snippet fallback must still apply the edit on a no-trailing-newline file.
    func testApplyEditsToleratesWhitespacePaddedSearch() throws {
        try write("b.txt", "Hello, world!")                          // no trailing newline
        let edits = [ProjectFiles.Edit(path: "b.txt", search: "\nHello, world!\n", replace: "Hello, AgentStudio!")]
        let r = ProjectFiles.applyEdits(cwd: tmp.path, edits: edits)
        XCTAssertEqual(r.applied, ["b.txt"])
        XCTAssertTrue(r.failed.isEmpty)
        XCTAssertEqual(read("b.txt"), "Hello, AgentStudio!")
    }

    /// The agent's path normalizer must turn the model's invented absolute roots (/app, /workspace)
    /// into clean project-relative paths, honor a real-root-absolute path, and alias tool names.
    func testAgentToolPathNormalizationAndAliases() {
        let runner = ToolRunner(cwd: "/tmp/proj", settings: .defaults, lane: .master)
        XCTAssertEqual(runner.rel("/app/note.txt"), "note.txt")
        XCTAssertEqual(runner.rel("/workspace/src/app.js"), "src/app.js")
        XCTAssertEqual(runner.rel("note.txt"), "note.txt")
        XCTAssertEqual(runner.rel("./a/b.txt"), "a/b.txt")
        XCTAssertEqual(runner.rel("/tmp/proj/x.txt"), "x.txt")          // real-root absolute → relative
        XCTAssertEqual(runner.rel("/app/app/x.txt"), "x.txt")          // peels repeated container roots
        XCTAssertEqual(ToolRunner.canonical("read_file"), "Read")
        XCTAssertEqual(ToolRunner.canonical("str_replace"), "Edit")
        XCTAssertEqual(ToolRunner.canonical("Bash"), "Bash")
        XCTAssertEqual(ToolRunner.canonical("list_files"), "list_files")
    }

    func testParseChangesSplitsFilesEditsProse() {
        let text = "做了点改动。\n<<<FILE: new.txt>>>\nhello\n<<<END FILE>>>\n<<<EDIT: a.js>>>\n<<<SEARCH>>>\nx\n<<<REPLACE>>>\ny\n<<<END EDIT>>>"
        let c = ProjectFiles.parseChanges(text)
        XCTAssertEqual(c.files.count, 1)
        XCTAssertEqual(c.edits.count, 1)
        XCTAssertEqual(c.prose, "做了点改动。")
    }

    // MARK: snapshots (R1 foundation)
    func testSnapshotDiffAndRestore() throws {
        try write("index.html", "v1")
        let s1 = SnapshotStore.snapshot(cwd: tmp.path, label: "first")
        XCTAssertNotNil(s1)
        try write("index.html", "v2")
        let s2 = SnapshotStore.snapshot(cwd: tmp.path, label: "second")
        let changes = SnapshotStore.changes(cwd: tmp.path, id: s2!.id)
        XCTAssertEqual(changes.first?.kind, .modified)
        XCTAssertEqual(changes.first?.before, "v1")
        XCTAssertEqual(changes.first?.after, "v2")
        SnapshotStore.restore(cwd: tmp.path, id: s1!.id)
        XCTAssertEqual(read("index.html"), "v1")                      // rolled back
    }

    // MARK: runner detection (R2)
    func testRunnerDetectsNodeAndStatic() throws {
        try write("package.json", #"{"scripts":{"dev":"vite"}}"#)
        XCTAssertEqual(ProjectRunner.detect(cwd: tmp.path)?.kind, .node)
        try FileManager.default.removeItem(at: tmp.appendingPathComponent("package.json"))
        try write("index.html", "<html></html>")
        XCTAssertEqual(ProjectRunner.detect(cwd: tmp.path)?.kind, .staticSite)
    }

    func testRunnerDetectsDevServerURL() {
        XCTAssertEqual(ProjectRunner.detectURL(in: "  ➜  Local:   http://localhost:5173/"), "http://localhost:5173/")
        XCTAssertEqual(ProjectRunner.detectURL(in: "running at http://0.0.0.0:3000"), "http://localhost:3000")
    }

    // MARK: pricing (R4)
    func testPricing() {
        let c = Pricing.cost(backend: .claude, model: "claude-opus-4-8", input: 1_000_000, output: 1_000_000)
        XCTAssertEqual(c, 30.0, accuracy: 0.001)                      // 5 in + 25 out
    }

    // MARK: MCP config (v2.0)
    func testMCPConfig() {
        let s = [MCPServer(id: "fs", command: "npx", args: ["-y", "pkg", "/p"], enabled: true)]
        let codex = MCPConfig.codexConfigArgs(s)
        XCTAssertTrue(codex.contains(#"mcp_servers.fs.command="npx""#))
        XCTAssertTrue(codex.contains(#"mcp_servers.fs.args=["-y","pkg","/p"]"#))
        let path = MCPConfig.claudeConfigFile(s)
        XCTAssertNotNil(path)
        let json = try? JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path!))) as? [String: Any]
        XCTAssertNotNil((json?["mcpServers"] as? [String: Any])?["fs"])
    }

    func testMCPPresets() {
        // filesystem fills in the project dir; others don't.
        let fs = MCPConfig.presets.first { $0.id == "filesystem" }!
        XCTAssertEqual(fs.server(projectDir: "/p").args.last, "/p")
        XCTAssertTrue(fs.server(projectDir: nil).args.last?.isEmpty == false)   // falls back to home
        let fetch = MCPConfig.presets.first { $0.id == "fetch" }!
        XCTAssertEqual(fetch.args(projectDir: "/p"), ["mcp-server-fetch"])      // no dir appended
        XCTAssertTrue(MCPConfig.presets.allSatisfy { !$0.command.isEmpty && !$0.id.isEmpty })
    }

    // MARK: templates (v1.4)
    func testTemplatesProduceRunnableFiles() {
        for t in TemplateLibrary.all {
            let files = t.files(.zh)
            XCTAssertFalse(files.isEmpty, "\(t.id) produced no files")
            XCTAssertTrue(files.contains { $0.path == "index.html" || $0.path == "package.json" }, "\(t.id) has no entry file")
            for f in files { XCTAssertFalse(f.content.isEmpty, "\(t.id) → \(f.path) empty") }
        }
    }
}
