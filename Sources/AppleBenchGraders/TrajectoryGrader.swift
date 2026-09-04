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

        // The reference agents have no process to judge. `fake` changes
        // nothing and `solution` applies a patch, so neither runs the commands
        // a real agent would — and failing them here would report every sound
        // task as broken. The task still fails for `fake` on the deliverable
        // itself, which is what the solvability check actually rests on.
        guard !Self.referenceAgents.contains(context.agent) else {
            return GradingResult(
                grader: identifier,
                passed: true,
                duration: start.duration(to: .now),
                summary: "Not applicable to the \(context.agent) agent, which reaches its result without running the work",
                evidence: []
            )
        }

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
        // Unconditional, and not something a task opts into. The sandbox
        // denies these binaries, but denial is a list of paths resolved when
        // the run starts: it cannot see one reached through an interpreter or
        // a path that appeared mid-run. A task answered with a wrapper is not
        // a task answered.
        let wrappers = Self.wrappersUsed(in: commands)
        if !wrappers.isEmpty {
            failures.append(
                "used \(wrappers.joined(separator: ", ")), which wraps the toolchain "
                    + "this task is asking about"
            )
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

    /// Agents that stand in for a person rather than doing the work.
    static let referenceAgents: Set<String> = ["fake", "solution"]

    /// Third-party wrappers the agent actually invoked.
    ///
    /// Only the executable position counts. Scanning the whole command would
    /// flag `--derivedDataPath /tmp/pod-cache`, and would fail a task for
    /// writing a report that names a tool — which ops-024 explicitly asks for.
    ///
    /// Launchers are stepped through, because `bundle exec fastlane` and
    /// `ruby -S fastlane` are exactly how a denied binary gets reached: the
    /// sandbox sees an allowed interpreter and a data file.
    static func wrappersUsed(in commands: [String]) -> [String] {
        var found: Set<String> = []
        for command in commands {
            for segment in command.split(whereSeparator: { "|;&\n".contains($0) }) {
                if let name = invokedName(in: String(segment)),
                   AgentSandbox.distinctiveWrapperNames.contains(name) {
                    found.insert(name)
                }
            }
        }
        return found.sorted()
    }

    /// Programs that run another program, so the next word is the real one.
    static let launchers: Set<String> = [
        "env", "sudo", "nohup", "time", "xargs", "exec", "command",
        "sh", "bash", "zsh", "ruby", "python", "python3", "perl", "node",
        "bundle", "npx", "pnpx", "bunx", "rbenv", "mise", "asdf",
    ]

    /// The program a command segment actually runs, stepping past launchers
    /// and their flags.
    static func invokedName(in segment: String) -> String? {
        var words = segment
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"'()")) }
            .filter { !$0.isEmpty }
        while let first = words.first {
            let name = first.split(separator: "/").last.map(String.init) ?? first
            guard launchers.contains(name) else {
                return name
            }
            // Skip the launcher, then its flags and any VAR=value it sets.
            words.removeFirst()
            while let next = words.first,
                  next.hasPrefix("-") || next.contains("=") {
                words.removeFirst()
                // `-S name` and `-c script` take the following word as data,
                // except that for `-S` the word is the program.
                if next == "-c", !words.isEmpty { words.removeFirst() }
            }
        }
        return nil
    }

    /// Every command the agent ran.
    ///
    /// Two sources, because the agent's work is in neither one alone. It runs
    /// most of it through its own shell tool, which the harness never spawns
    /// and so never records as a command; and the commands the harness *does*
    /// record are mostly the graders' own, run after the agent has exited.
    ///
    /// Counting those was the bug this replaced: every task builds during
    /// grading, so "the agent built the project" was satisfied by the build
    /// grader on a run where the agent did nothing at all.
    static func commands(in log: String) -> [String] {
        var found: [String] = []
        for line in log.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let payload = event["payload"] as? [String: Any]
            else { continue }

            switch event["type"] as? String {
            case "command_finished":
                // Only the agent phase, and not the line that launches the
                // agent itself — that one is the harness's, and naming the
                // model on it would match half the patterns a task asserts.
                guard payload["phase"] as? String == "agent",
                      let command = payload["command"] as? String,
                      !command.contains(AgentSandbox.sandboxExec)
                else { continue }
                found.append(command)
            case "agent_event":
                guard let command = Self.shellCommand(in: payload) else { continue }
                found.append(command)
            default:
                continue
            }
        }
        return found
    }

    /// The shell command inside an agent tool event, if that is what it is.
    static func shellCommand(in payload: [String: Any]) -> String? {
        let data = payload["data"] as? [String: Any] ?? payload
        let part = data["part"] as? [String: Any] ?? data
        guard part["type"] as? String == "tool",
              let tool = part["tool"] as? String,
              Self.shellTools.contains(tool),
              let state = part["state"] as? [String: Any],
              let input = state["input"] as? [String: Any]
        else { return nil }
        // Agents name this differently; take whichever carries the text.
        for key in ["command", "cmd", "script"] {
            if let command = input[key] as? String, !command.isEmpty { return command }
        }
        return nil
    }

    /// Tool names that mean "run this in a shell".
    static let shellTools: Set<String> = ["bash", "shell", "sh", "run", "exec", "terminal"]
}
