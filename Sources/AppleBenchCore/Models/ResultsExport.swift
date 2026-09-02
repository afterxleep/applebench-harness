import Foundation

/// Machine-readable renderings of a set of runs.
///
/// The CLI's table output is for a human at a terminal. These are the formats
/// something downstream consumes — a leaderboard, a spreadsheet, or the
/// benchmark pages on the site — so the numbers published anywhere trace back
/// to `result.json` files rather than to a hand-maintained copy.
///
/// Raw variables stay raw. Absent data stays absent: a run that reported no
/// token usage exports an empty `total_tokens` cell, never a zero.
///
/// The one derived quantity here is the AppleBench score, and it is derived
/// *here* on purpose. The site's charts and tables read these exports and sum
/// them; if points were computed in the page template instead, the published
/// number and the data it links to could disagree. See ``AppleBenchScore`` for
/// the formula and why its terms are independent of the rest of the set.
public enum ResultsExport {
    /// Column order for `csv(for:)`, also used as the header row.
    static let csvColumns = [
        "task", "category", "difficulty", "agent", "model", "passed",
        "duration_seconds", "agent_termination", "input_tokens", "output_tokens",
        "total_tokens", "cost_usd", "files_changed", "insertions", "deletions",
        "face_value", "efficiency", "points",
        "graders", "grader_summaries", "run_id",
    ]

    /// RFC 4180 CSV, one row per run, in the given order.
    public static func csv(for results: [BenchmarkRunResult]) -> String {
        var lines = [csvColumns.joined(separator: ",")]
        for result in results {
            let fields: [String] = [
                result.task,
                result.category?.rawValue ?? "",
                result.difficulty.map(String.init) ?? "",
                result.agent.agent,
                result.agent.model ?? "",
                result.result.passed ? "true" : "false",
                String(format: "%.1f", result.result.durationSeconds),
                result.result.agentTermination.rawValue,
                result.usage.inputTokens.map(String.init) ?? "",
                result.usage.outputTokens.map(String.init) ?? "",
                result.usage.totalTokens.map(String.init) ?? "",
                result.usage.estimatedCostUSD.map { String(format: "%.4f", $0) } ?? "",
                String(result.git.filesChanged),
                String(result.git.insertions),
                String(result.git.deletions),
                String(AppleBenchScore.faceValue(difficulty: result.difficulty)),
                String(format: "%.2f", AppleBenchScore.efficiency(totalTokens: result.usage.totalTokens)),
                String(format: "%.1f", AppleBenchScore.points(for: result)),
                result.graders.map { "\($0.name)=\($0.passed ? "P" : "F")" }.joined(separator: ";"),
                result.graders.map { "\($0.name):\($0.summary)" }.joined(separator: " | "),
                result.runID,
            ]
            lines.append(fields.map(escapeCSV).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// A field is quoted when it contains a delimiter, a quote, or a newline;
    /// embedded quotes are doubled. Without this a grader summary carrying a
    /// compiler error would split into extra columns.
    static func escapeCSV(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Aggregate JSON: headline totals, per-category totals, per-configuration
    /// totals, and every run. Suitable to commit alongside a published report.
    public static func json(
        for results: [BenchmarkRunResult],
        attempt: AttemptSelection = .all
    ) throws -> Data {
        let document = Summary(results: results, attempt: attempt)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(document)
    }

    // MARK: - Aggregation

    public struct Summary: Encodable {
        public var total: Int
        public var passed: Int
        public var completionRate: Double
        public var score: AppleBenchScore.Total
        /// Which attempt counted, when a task was run more than once. Recorded
        /// because the headline moves with it and the runs cannot say it.
        public var attempt: String
        public var categories: [CategoryTotals]
        public var configurations: [ConfigurationTotals]
        public var runs: [BenchmarkRunResult]

        enum CodingKeys: String, CodingKey {
            case total, passed, score, attempt, categories, configurations, runs
            case completionRate = "completion_rate"
        }

        public init(results: [BenchmarkRunResult], attempt: AttemptSelection = .all) {
            total = results.count
            passed = results.count { $0.result.passed }
            completionRate = results.isEmpty ? 0 : Double(passed) / Double(results.count)
            score = AppleBenchScore.total(for: results)
            self.attempt = attempt.rawValue

            // `uncategorized` is an explicit bucket rather than a silent drop:
            // a run whose task predates the category schema still counts.
            let grouped = Dictionary(grouping: results) { $0.category?.rawValue ?? "uncategorized" }
            categories = grouped
                .map { CategoryTotals(category: $0.key, results: $0.value) }
                .sorted { $0.category < $1.category }

            let byConfiguration = Dictionary(grouping: results) { result in
                result.agent.model.map { "\(result.agent.agent) · \($0)" } ?? result.agent.agent
            }
            configurations = byConfiguration
                .map { ConfigurationTotals(label: $0.key, results: $0.value) }
                .sorted { $0.label < $1.label }

            runs = results.sorted { $0.task < $1.task }
        }
    }

    public struct CategoryTotals: Encodable {
        public var category: String
        public var total: Int
        public var passed: Int
        public var completionRate: Double
        public var score: AppleBenchScore.Total

        enum CodingKeys: String, CodingKey {
            case category, total, passed, score
            case completionRate = "completion_rate"
        }

        init(category: String, results: [BenchmarkRunResult]) {
            self.category = category
            total = results.count
            passed = results.count { $0.result.passed }
            completionRate = results.isEmpty ? 0 : Double(passed) / Double(results.count)
            score = AppleBenchScore.total(for: results)
        }
    }

    public struct ConfigurationTotals: Encodable {
        public var label: String
        public var agent: String
        public var model: String?
        public var total: Int
        public var passed: Int
        public var completionRate: Double
        public var score: AppleBenchScore.Total
        public var medianDurationSeconds: Double?
        /// Summed only over runs that reported the value; `nil` when none did.
        public var totalTokens: Int?
        public var totalCostUSD: Double?
        public var costPerSolvedTaskUSD: Double?

        enum CodingKeys: String, CodingKey {
            case label, agent, model, total, passed, score
            case completionRate = "completion_rate"
            case medianDurationSeconds = "median_duration_seconds"
            case totalTokens = "total_tokens"
            case totalCostUSD = "total_cost_usd"
            case costPerSolvedTaskUSD = "cost_per_solved_task_usd"
        }

        init(label: String, results: [BenchmarkRunResult]) {
            self.label = label
            agent = results.first?.agent.agent ?? ""
            model = results.first?.agent.model
            total = results.count
            passed = results.count { $0.result.passed }
            completionRate = results.isEmpty ? 0 : Double(passed) / Double(results.count)
            score = AppleBenchScore.total(for: results)
            medianDurationSeconds = Self.median(results.map(\.result.durationSeconds))

            let tokens = results.compactMap(\.usage.totalTokens)
            totalTokens = tokens.isEmpty ? nil : tokens.reduce(0, +)
            let costs = results.compactMap(\.usage.estimatedCostUSD)
            totalCostUSD = costs.isEmpty ? nil : costs.reduce(0, +)
            costPerSolvedTaskUSD = (totalCostUSD.map { passed > 0 ? $0 / Double(passed) : nil }) ?? nil
        }

        static func median(_ values: [Double]) -> Double? {
            guard !values.isEmpty else { return nil }
            let sorted = values.sorted()
            let middle = sorted.count / 2
            return sorted.count.isMultiple(of: 2)
                ? (sorted[middle - 1] + sorted[middle]) / 2
                : sorted[middle]
        }
    }
}
