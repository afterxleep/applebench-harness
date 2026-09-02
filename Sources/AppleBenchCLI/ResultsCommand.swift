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

    func run() async throws {
        let root = URL(fileURLWithPath: path ?? Wiring.defaultRunsRoot().path)
        let collected = Self.collectResults(under: root)
        guard !collected.isEmpty else {
            FileHandle.standardError.write(Data("No result.json files found under \(root.path)\n".utf8))
            throw ExitCode.failure
        }

        let matching = model.map { wanted in collected.filter { $0.agent.model == wanted } } ?? collected
        guard !matching.isEmpty else {
            FileHandle.standardError.write(Data("No runs under \(root.path) used model \(model ?? "")\n".utf8))
            throw ExitCode.failure
        }
        let results = attempt.apply(to: matching)

        switch format {
        case .csv:
            try emit(Data(ResultsExport.csv(for: results.sorted { $0.task < $1.task }).utf8))
            return
        case .json:
            try emit(try ResultsExport.json(for: results, attempt: attempt))
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
        // raw sum or rate; the score is `points-v1`, computed per run.
        let byAgent = Dictionary(grouping: results, by: { configurationLabel(of: $0) })
        let nameWidth = max(14, (byAgent.keys.map(\.count).max() ?? 0) + 2)
        print("\(Format.pad("", nameWidth))\(Format.pad("Points", 14))\(Format.pad("Passed", 9))\(Format.pad("Completion", 12))\(Format.pad("Tokens", 10))\(Format.pad("Cost", 10))Cost/solve")
        for (agent, agentResults) in byAgent.sorted(by: { $0.key < $1.key }) {
            let passed = agentResults.count { $0.result.passed }
            let score = AppleBenchScore.total(for: agentResults)
            let tokens = agentResults.compactMap(\.usage.totalTokens).reduce(into: nil as Int?) { $0 = ($0 ?? 0) + $1 }
            let cost = agentResults.compactMap(\.usage.estimatedCostUSD).reduce(into: nil as Double?) { $0 = ($0 ?? 0) + $1 }
            let perSolve: String = {
                guard let cost, passed > 0 else { return "-" }
                return Format.cost(cost / Double(passed))
            }()
            print(
                Format.pad(agent, nameWidth)
                + Format.pad("\(Int(score.points.rounded()))/\(score.available)", 14)
                + Format.pad("\(passed)/\(agentResults.count)", 9)
                + Format.pad(Format.percent(Double(passed) / Double(agentResults.count)), 12)
                + Format.pad(tokens.map(String.init) ?? "-", 10)
                + Format.pad(cost.map(Format.cost) ?? "-", 10)
                + perSolve
            )
        }

        print("\nScore: \(AppleBenchScore.specification), attempt rule: \(attempt.rawValue).")
    }

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

    static func collectResults(under root: URL) -> [BenchmarkRunResult] {
        var results: [BenchmarkRunResult] = []
        let direct = root.appendingPathComponent("result.json")
        if FileManager.default.fileExists(atPath: direct.path),
           let result = try? BenchmarkRunResult.read(from: direct) {
            return [result]
        }
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        for case let url as URL in enumerator where url.lastPathComponent == "result.json" {
            if let result = try? BenchmarkRunResult.read(from: url) {
                results.append(result)
            }
        }
        return results
    }
}
