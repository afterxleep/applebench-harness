import AppleBenchCore
import ArgumentParser
import Foundation

/// Computes empirical task weights from complete model runs and writes them
/// as the JSON file the results command scores against.
///
/// Every argument is a run directory containing `result.json` files for one
/// or more complete model configurations. Each distinct agent·model pair
/// counts as one model for the weights; a task only some models ran is
/// weighted by the models that ran it.
struct WeightsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "weights",
        abstract: "Derive empirical task weights from complete model runs."
    )

    @Argument(help: "Run directories holding the complete runs to weight from.")
    var paths: [String]

    @Option(name: .long, help: "Write the weights JSON to this file instead of stdout.")
    var output: String?

    func run() throws {
        var runsByModel: [String: [BenchmarkRunResult]] = [:]
        for path in paths {
            let root = URL(fileURLWithPath: path)
            let results = ResultsCommand.collectResults(under: root)
            guard !results.isEmpty else {
                throw ValidationError("No result.json files found under \(root.path)")
            }
            for result in results {
                let key = result.agent.model.map { "\(result.agent.agent) · \($0)" } ?? result.agent.agent
                runsByModel[key, default: []].append(result)
            }
        }

        let weights = AppleBenchScore.weights(for: runsByModel)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(weights.sorted { $0.key < $1.key }.reduce(into: [:]) { $0[$1.key] = $1.value })
        if let output {
            try data.write(to: URL(fileURLWithPath: output))
            FileHandle.standardError.write(Data("Wrote \(weights.count) task weights to \(output)\n".utf8))
        } else {
            FileHandle.standardOutput.write(data)
        }
    }
}
