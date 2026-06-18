import Foundation

/// R4 — cost metering. Estimated per-million-token prices and a day-bucketed usage ledger that
/// powers the cost chip and the monthly budget. Prices are approximate (providers change them and
/// custom proxies vary) — this is a spend *estimate*, surfaced as such in the UI.
enum Pricing {
    struct Rate: Sendable { var input: Double; var output: Double } // USD per 1M tokens

    static func rate(backend: Backend, model: String) -> Rate {
        let m = model.lowercased()
        switch backend {
        case .claude:
            if m.contains("opus") { return Rate(input: 5, output: 25) }
            if m.contains("sonnet") { return Rate(input: 3, output: 15) }
            if m.contains("haiku") { return Rate(input: 1, output: 5) }
            return Rate(input: 5, output: 25)
        case .codex: // OpenAI — rough public list prices; user models vary widely
            if m.contains("mini") { return Rate(input: 0.15, output: 0.60) }
            if m.contains("o1") || m.contains("o3") { return Rate(input: 15, output: 60) }
            if m.contains("4o") || m.contains("gpt-4") { return Rate(input: 2.5, output: 10) }
            return Rate(input: 2.5, output: 10)
        case .deepseek:
            if m.contains("flash") { return Rate(input: 0.27, output: 1.10) }
            return Rate(input: 0.55, output: 2.20)
        }
    }

    static func cost(backend: Backend, model: String, input: Int, output: Int) -> Double {
        let r = rate(backend: backend, model: model)
        return Double(input) / 1_000_000 * r.input + Double(output) / 1_000_000 * r.output
    }
}

/// One day's accumulated usage.
struct DayUsage: Codable, Sendable, Hashable {
    var input = 0
    var output = 0
    var cost = 0.0
    var calls = 0
}

/// The full ledger: "yyyy-MM-dd" → usage. Summed on demand for today / this month / all time.
struct UsageLedger: Codable, Sendable, Hashable {
    var days: [String: DayUsage] = [:]

    mutating func add(dayKey: String, input: Int, output: Int, cost: Double) {
        var d = days[dayKey] ?? DayUsage()
        d.input += input; d.output += output; d.cost += cost; d.calls += 1
        days[dayKey] = d
    }

    func total() -> DayUsage { days.values.reduce(into: DayUsage()) { acc, d in
        acc.input += d.input; acc.output += d.output; acc.cost += d.cost; acc.calls += d.calls
    } }

    func cost(forPrefix prefix: String) -> Double {
        days.reduce(0) { $0 + ($1.key.hasPrefix(prefix) ? $1.value.cost : 0) }
    }
}

/// Loads/saves the ledger off the main actor. The on-disk file is a single small JSON.
enum CostStore {
    private static var file: URL { AppPaths.usageFile }

    static func load() -> UsageLedger {
        guard let data = try? Data(contentsOf: file),
              let led = try? JSONDecoder().decode(UsageLedger.self, from: data) else { return UsageLedger() }
        return led
    }

    static func save(_ ledger: UsageLedger) {
        if let data = try? JSONEncoder().encode(ledger) { try? data.write(to: file, options: .atomic) }
    }

    /// "yyyy-MM-dd" / "yyyy-MM" keys for the given date in the user's calendar.
    static func dayKey(_ date: Date = Date()) -> String { keyFormatter("yyyy-MM-dd").string(from: date) }
    static func monthKey(_ date: Date = Date()) -> String { keyFormatter("yyyy-MM").string(from: date) }

    private static func keyFormatter(_ fmt: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = fmt
        return f
    }
}
