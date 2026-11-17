import AppleBenchCore
import ArgumentParser
import Foundation

// The rule is a Core concept; parsing it from a flag is a CLI concern, so the
// conformance lives here rather than making Core depend on ArgumentParser.
extension AttemptSelection: ExpressibleByArgument {}

/// Reads machine-readable results from disk and prints a summary — the same
/// aggregation a leaderboard would compute from `result.json` files.
struct ResultsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "results",
        abstract: "Summarize result.json files under a path."
    )

    enum OutputFormat: String, ExpressibleByArgument, CaseIterable {
        case table
        case csv
        case json
    }

    @Argument(help: "A run directory, or any directory containing runs (default: .applebench/runs).")
    var path: String?

    @Option(name: .long, help: "Output format: table (default), csv, or json.")
    var format: OutputFormat = .table

    @Option(name: .long, help: "Write the output to this file instead of stdout.")
    var output: String?

    @Option(
        name: .long,
        help: """
        Which attempt counts when a task was run more than once, per configuration: \
        all (default), first, latest, or best.
        """
    )
    var attempt: AttemptSelection = .all

    @Option(name: .long, help: "Only include runs from this model id.")
    var model: String?

    @Option(
        name: .long,
        help: """
        Empirical task weights JSON (task id -> points), used by the \
        empirical-v1 score. Defaults to the published weights at \
        site/_data/empirical_weights.json. An explicitly named file that is \
        missing is an error; scores must never silently fall back to another \
        weighting.
        """
    )
    var weights: String?

    @Flag(
        name: .long,
        help: "Fail when no task weights can be loaded, instead of exporting an unscored report."
    )
    var requireWeights = false

    @Option(
        name: .long,
        parsing: .singleValue,
        help: "Previous report JSON used as an immutable baseline (repeatable). Live run artifacts with the same run id take precedence."
    )
    var baseReport: [String] = []

    @Option(
        name: .long,
        help: "Path to a suite YAML. Only tasks listed in it are included, so an export cannot quietly carry a run of something outside the scored set. Repeat it when a score spans several suites."
    )
    var suite: [String] = []

    @Option(
        name: .long,
        help: "Path to the pinned model catalog (default: Data/model-catalog.json). Supplies the list prices cost is computed from and the effort ladder each model exposes."
    )
    var catalog: String?

    /// Loads the pinned catalog, or `nil` when there is none to load.
    ///
    /// A missing catalog is not fatal: the export simply omits list cost
    /// rather than inventing a price. An *unreadable* one is fatal, because
    /// silently falling back would publish a report that looks complete and
    /// has quietly dropped the only comparable cost figure in it.
    func loadCatalog() throws -> ModelCatalog? {
        let path = catalog ?? "Data/model-catalog.json"
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            if catalog != nil {
                throw ValidationError("No model catalog at \(path).")
            }
            return nil
        }
        return try ModelCatalog.load(from: url)
    }

    func run() async throws {
        let root = URL(fileURLWithPath: path ?? Wiring.defaultRunsRoot().path)
        let collected = try ResultCollection.merged(
            baseReports: baseReport.map { URL(fileURLWithPath: $0) },
            live: Self.collectResults(under: root)
        )
        guard !collected.isEmpty else {
            FileHandle.standardError.write(Data("No result.json files found under \(root.path)\n".utf8))
            throw ExitCode.failure
        }

        var matching = model.map { wanted in collected.filter { $0.agent.model == wanted } } ?? collected
        if !suite.isEmpty {
            // A published score is a fraction of a stated set of tasks. A run
            // directory accumulates whatever was run in it — including the
            // public sample tasks, which must never be scored — so the export
            // is filtered by the suite rather than trusted to contain only it.
            var identifiers: Set<String> = []
            for path in suite {
                identifiers.formUnion(try Self.taskIdentifiers(inSuiteAt: path))
            }
            let dropped = Set(matching.map(\.task)).subtracting(identifiers).sorted()
            matching = matching.filter { identifiers.contains($0.task) }
            if !dropped.isEmpty {
                FileHandle.standardError.write(Data(
                    ("Excluded \(dropped.count) task(s) not in the suite: "
                        + dropped.joined(separator: ", ") + "\n").utf8
                ))
            }
        }
        guard !matching.isEmpty else {
            FileHandle.standardError.write(Data("No runs under \(root.path) used model \(model ?? "")\n".utf8))
            throw ExitCode.failure
        }
        let results = attempt.apply(to: matching)

        let prices = try loadCatalog()
        let taskWeights = try loadWeights()

        switch format {
        case .csv:
            try emit(Data(ResultsExport.csv(
                for: results.sorted { $0.task < $1.task },
                catalog: prices,
                weights: taskWeights
            ).utf8))
            return
        case .json:
            try emit(try ResultsExport.json(for: results, attempt: attempt, catalog: prices, weights: taskWeights))
            return
        case .table:
            break
        }

        print("AppleBench · \(results.count) run(s) under \(root.path)\n")

        let agentWidth = max(14, (results.map { configurationLabel(of: $0).count }.max() ?? 0) + 2)
        let width = max(14, (results.map(\.task.count).max() ?? 0) + 2)

        // Runs are grouped by category so a reader sees which capability is
        // weak, not just which tasks failed. Runs from tasks predating the
        // category schema fall into an explicit "uncategorized" group rather
        // than being silently folded into one of the six.
        let groups = Dictionary(grouping: results, by: { $0.category })
        let orderedCategories: [BenchmarkCategory?] = BenchmarkCategory.allCases.filter { groups[$0] != nil }
        let ordered: [BenchmarkCategory?] = orderedCategories + (groups[BenchmarkCategory?.none] != nil ? [nil] : [])

        for category in ordered {
            guard let group = groups[category] else { continue }
            let passed = group.count { $0.result.passed }
            print("\(category?.rawValue ?? "uncategorized")  (\(passed)/\(group.count))")
            print("  \(Format.pad("Task", width))\(Format.pad("Diff", 6))\(Format.pad("Agent", agentWidth))\(Format.pad("Result", 8))\(Format.pad("Time", 8))\(Format.pad("Tokens", 10))\(Format.pad("Cost", 10))Termination")
            for result in group.sorted(by: { $0.runID < $1.runID }) {
                let tokens = result.usage.totalTokens.map(String.init) ?? "-"
                let cost = result.usage.estimatedCostUSD.map(Format.cost) ?? "-"
                print(
                    "  "
                    + Format.pad(result.task, width)
                    + Format.pad(result.difficulty.map(String.init) ?? "-", 6)
                    + Format.pad(configurationLabel(of: result), agentWidth)
                    + Format.pad(Format.passFail(result.result.passed), 8)
                    + Format.pad(Format.duration(result.result.durationSeconds), 8)
                    + Format.pad(tokens, 10)
                    + Format.pad(cost, 10)
                    + result.result.agentTermination.rawValue
                )
            }
            print("")
        }

        // Aggregate per agent+model configuration, so model comparisons through
        // a single harness stay separated. Everything but the score column is a
        // raw sum or rate; points are computed independently per run.
        let byAgent = Dictionary(grouping: results, by: { configurationLabel(of: $0) })
        let nameWidth = max(14, (byAgent.keys.map(\.count).max() ?? 0) + 2)
        print("\(Format.pad("", nameWidth))\(Format.pad("Score", 14))\(Format.pad("Passed", 9))\(Format.pad("Completion", 12))\(Format.pad("Tokens", 10))\(Format.pad("Cost", 10))Cost/pct-pt")
        for (agent, agentResults) in byAgent.sorted(by: { $0.key < $1.key }) {
            let passed = agentResults.count { $0.result.passed }
            let score = AppleBenchScore.total(for: agentResults, weights: taskWeights)
            let tokens = agentResults.compactMap(\.usage.totalTokens).reduce(into: nil as Int?) { $0 = ($0 ?? 0) + $1 }
            let cost = agentResults.compactMap(\.usage.estimatedCostUSD).reduce(into: nil as Double?) { $0 = ($0 ?? 0) + $1 }
            let perPoint: String = {
                guard let cost, score.percentage > 0 else { return "-" }
                return Format.cost(cost / score.percentage)
            }()
            print(
                Format.pad(agent, nameWidth)
                + Format.pad("\(score.points)/\(score.available)", 14)
                + Format.pad("\(passed)/\(agentResults.count)", 9)
                + Format.pad(Format.percent(Double(passed) / Double(agentResults.count)), 12)
                + Format.pad(tokens.map(String.init) ?? "-", 10)
                + Format.pad(cost.map(Format.cost) ?? "-", 10)
                + perPoint
            )
        }

        print("\nScore: \(AppleBenchScore.specification), attempt rule: \(attempt.rawValue), \(taskWeights.count) task weight(s).")
    }

    /// Loads the empirical task weights the score is computed against.
    ///
    /// A missing default file is not fatal on its own: the export still
    /// carries every raw verdict and marks the score unscored, unless
    /// `requireWeights` was set. An explicitly named file that is missing is
    /// fatal, because a caller who named a weighting expects that weighting.
    func loadWeights() throws -> [String: Int] {
        let path = weights ?? Self.defaultWeightsPath
        guard FileManager.default.fileExists(atPath: path) else {
            if weights != nil {
                throw ValidationError("No task weights file at \(path).")
            }
            if requireWeights {
                throw ValidationError(
                    "No task weights at the default path \(path). Run `applebench weights` "
                        + "or pass --weights; refusing to publish an unscored report."
                )
            }
            FileHandle.standardError.write(Data(
                "warning: no task weights at \(path); the score will be unscored\n".utf8
            ))
            return [:]
        }
        let decoded = try JSONDecoder().decode([String: Int].self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        return decoded.filter { _, weight in weight > 0 }
    }

    static let defaultWeightsPath = "site/_data/empirical_weights.json"

    private func emit(_ data: Data) throws {
        guard let output else {
            FileHandle.standardOutput.write(data)
            return
        }
        try data.write(to: URL(fileURLWithPath: output))
        FileHandle.standardError.write(Data("Wrote \(data.count) bytes to \(output)\n".utf8))
    }

    private func configurationLabel(of result: BenchmarkRunResult) -> String {
        result.agent.model.map { "\(result.agent.agent) · \($0)" } ?? result.agent.agent
    }

    /// Task ids listed in a suite file. Parsed with a line reader because the
    /// shape is fixed and the CLI layer carries no YAML dependency.
    static func taskIdentifiers(inSuiteAt path: String) throws -> Set<String> {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            throw ValidationError("No suite file at \(path)")
        }
        var identifiers: Set<String> = []
        var inTasks = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("tasks:") { inTasks = true; continue }
            guard inTasks else { continue }
            if trimmed.hasPrefix("- ") {
                identifiers.insert(String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces))
            } else if !trimmed.isEmpty, !trimmed.hasPrefix("#") {
                break
            }
        }
        guard !identifiers.isEmpty else {
            throw ValidationError("Suite at \(path) lists no tasks")
        }
        return identifiers
    }

    static func collectResults(under root: URL) -> [BenchmarkRunResult] {
        var results: [BenchmarkRunResult] = []
        let direct = root.appendingPathComponent("result.json")
        if FileManager.default.fileExists(atPath: direct.path),
           let result = try? BenchmarkRunResult.readForAggregation(from: direct) {
            return [result]
        }
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        for case let url as URL in enumerator where url.lastPathComponent == "result.json" {
            if let result = try? BenchmarkRunResult.readForAggregation(from: url) {
                results.append(result)
            }
        }
        return results
    }
}
