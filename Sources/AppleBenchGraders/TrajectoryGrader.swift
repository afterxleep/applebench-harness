import AppleBenchCore
import Foundation

/// Judges what the agent did, from the harness's own record of it.
///
/// Every command the agent runs is spawned by the harness and written to
/// `events.jsonl`. That record is the one thing in a run the agent cannot
/// write, which makes it the only sound way to grade a deliverable the agent
/// produces itself: an artifact says what the agent wants it to say, and the
/// trajectory says what actually happened.
public struct TrajectoryGrader: Grader {
    public let identifier = "trajectory"
    private let configuration: TrajectoryGraderConfiguration

    public init(configuration: TrajectoryGraderConfiguration) {
        self.configuration = configuration
    }

    public func grade(task: BenchmarkTask, context: GradingContext) async throws -> GradingResult {
        let start = ContinuousClock.now
        try configuration.validate()

        let log = context.runDirectoryURL.appendingPathComponent("events.jsonl")
        guard let text = try? String(contentsOf: log, encoding: .utf8) else {
            throw BenchmarkFailure.graderFailure(
                grader: identifier,
                message: "No events.jsonl for this run, so what the agent did cannot be read."
            )
        }
        let commands = Self.commands(in: text)
        var failures: [String] = []

        if let minimum = configuration.minCommands, commands.count < minimum {
            failures.append("ran \(commands.count) command(s), fewer than the \(minimum) required")
        }
        if let minimum = configuration.minBuildInvocations {
            let builds = commands.count { $0.contains("xcodebuild") && !$0.contains(" test") }
            if builds < minimum {
                failures.append("built \(builds) time(s), fewer than the \(minimum) required")
            }
        }
        if let minimum = configuration.minTestInvocations {
            let tests = commands.count { $0.contains("xcodebuild") && $0.contains(" test") }
            if tests < minimum {
                failures.append("ran tests \(tests) time(s), fewer than the \(minimum) required")
            }
        }
        for assertion in configuration.assertions {
            guard let pattern = assertion.commandMatches,
                  let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let hits = commands.count { command in
                regex.firstMatch(in: command, range: NSRange(command.startIndex..., in: command)) != nil
            }
            if assertion.absent == true {
                if hits > 0 { failures.append("ran a command matching /\(pattern)/, which this task forbids") }
            } else if hits < (assertion.atLeast ?? 1) {
                failures.append("ran \(hits) command(s) matching /\(pattern)/, fewer than the \(assertion.atLeast ?? 1) required")
            }
        }

        return GradingResult(
            grader: identifier,
            passed: failures.isEmpty,
            duration: start.duration(to: .now),
            summary: failures.isEmpty
                ? "The agent's recorded commands show the work behind the deliverable (\(commands.count) command(s))"
                : "The deliverable is not backed by the run: " + failures.joined(separator: "; "),
            evidence: []
        )
    }

    /// Every command the harness observed the agent finish.
    static func commands(in log: String) -> [String] {
        var found: [String] = []
        for line in log.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  event["type"] as? String == "command_finished",
                  let payload = event["payload"] as? [String: Any],
                  let command = payload["command"] as? String
            else { continue }
            found.append(command)
        }
        return found
    }
}
