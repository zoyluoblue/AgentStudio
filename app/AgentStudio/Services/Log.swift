import Foundation
import OSLog

/// Structured logger — JSONL lines to logs/agentstudio.log plus os.Logger for the console.
/// A `sink` can be attached so the (future) in-app log view receives lines live.
/// Thread-safe: callable synchronously from any actor or the main thread.
final class Log: @unchecked Sendable {
    static let shared = Log()

    private let queue = DispatchQueue(label: "com.example.agentstudio.log")
    private let logger = Logger(subsystem: "com.example.agentstudio", category: "app")
    private var handle: FileHandle?
    private var sink: (@Sendable (String) -> Void)?

    private init() {
        queue.async { [weak self] in
            let url = AppPaths.logFile
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            self?.handle = try? FileHandle(forWritingTo: url)
            _ = try? self?.handle?.seekToEnd()
        }
    }

    func setSink(_ sink: (@Sendable (String) -> Void)?) {
        queue.async { [weak self] in self?.sink = sink }
    }

    /// Log a named event with an optional key/value payload (rendered as JSON).
    func event(_ name: String, _ data: [String: Any] = [:]) {
        let ts = ISO8601DateFormatter().string(from: Date())
        var payload = data
        payload["t"] = ts
        payload["evt"] = name
        let line: String
        if let json = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
           let str = String(data: json, encoding: .utf8) {
            line = str
        } else {
            line = "{\"evt\":\"\(name)\"}"
        }
        logger.debug("\(line, privacy: .public)")
        queue.async { [weak self] in
            guard let self else { return }
            if let data = (line + "\n").data(using: .utf8) {
                try? self.handle?.write(contentsOf: data)
            }
            self.sink?(line)
        }
    }
}
