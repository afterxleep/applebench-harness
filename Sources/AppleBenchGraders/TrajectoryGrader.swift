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

        let protectedAccesses = Self.protectedHarnessAccesses(
            in: text,
            runDirectory: context.runDirectoryURL,
            workspace: context.workspaceURL
        )
        if !protectedAccesses.isEmpty {
            failures.append(
                "accessed protected benchmark material outside its workspace "
                    + "in \(protectedAccesses.count) tool event(s)"
            )
        }

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
        // A wrapper the agent reached for is recorded, not punished. What a
        // task asks is whether the work was done, and a deliverable produced
        // with fastlane is still the deliverable. The sandbox denies the
        // wrappers installed on this machine, so a published run measures the
        // toolchain rather than the operator's setup — but that is a property
        // of the environment, not a verdict on the model.
        //
        // The check fired three times in its life and was wrong all three:
        // twice on Xcode's own xcbuild, once on `gem list` asking what was
        // installed. It never once caught a wrapper doing the work.
        let wrappers = Self.wrappersUsed(in: Self.commandsWithOutput(in: text))

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
                ? "The agent's recorded commands show the work behind the deliverable (\(commands.count) command(s)"
                    + (wrappers.isEmpty ? ")" : ", including \(wrappers.joined(separator: ", ")))")
                : "The deliverable is not backed by the run: " + failures.joined(separator: "; "),
            evidence: []
        )
    }

    /// Agents that stand in for a person rather than doing the work.
    static let referenceAgents: Set<String> = ["fake", "solution"]

    /// Agent tool calls that reached the harness checkout rather than the
    /// current workspace. The macOS sandbox is the primary boundary; this is
    /// the independent audit trail that turns any escape into a failed
    /// trajectory instead of a publishable result.
    ///
    /// A call the sandbox refused reached nothing, so it is not counted: an
    /// agent that guesses its workspace is the folder above and is turned away
    /// has neither cheated nor escaped. Anything short of a clear refusal
    /// still counts.
    static func protectedHarnessAccesses(
        in log: String,
        runDirectory: URL,
        workspace: URL
    ) -> [String] {
        let runsDirectory = runDirectory.deletingLastPathComponent()
        guard runsDirectory.lastPathComponent == "runs" else { return [] }
        let benchmarkDirectory = runsDirectory.deletingLastPathComponent()
        guard benchmarkDirectory.lastPathComponent == ".applebench" else { return [] }
        let harnessRoot = benchmarkDirectory.deletingLastPathComponent().standardizedFileURL.path
        let workspacePath = workspace.standardizedFileURL.path
        // The run's own directory, and the agent configuration the harness
        // writes into it, are the agent's own working furniture: the config is
        // read back by the agent CLI itself, and a listing of the directory
        // names files without opening them. Everything inside it — the event
        // log, the sandbox profile, the grading logs — stays protected.
        let ownDirectory = runDirectory.standardizedFileURL.path
        let ownFurniture = [ownDirectory + "/opencode.json", ownDirectory]

        var accesses: [String] = []
        for line in log.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  event["type"] as? String == "agent_event",
                  let payload = event["payload"] as? [String: Any],
                  let state = Self.toolState(in: payload),
                  let input = state["input"]
            else { continue }

            let strings = Self.strings(in: Self.withoutWrittenContent(input))
            let references = Set(strings.flatMap { value in
                value.replacingOccurrences(of: workspacePath, with: "")
                    .split(whereSeparator: { $0.isWhitespace || "\"'`;|&<>()=".contains($0) })
                    .map(String.init)
                    .filter { token in
                        token.contains(harnessRoot)
                            && !ownFurniture.contains(token.hasSuffix("/") ? String(token.dropLast()) : token)
                    }
            })
            guard !references.isEmpty,
                  !Self.wasRefused(
                      state,
                      tool: Self.toolName(in: payload),
                      references: references,
                      // The workspace lives inside the harness checkout, so a
                      // command naming its own files mentions the harness root
                      // in passing. Only what is left after removing it says
                      // where the command actually reached.
                      strippingOwnPaths: [workspacePath] + ownFurniture
                  )
            else { continue }
            accesses.append(strings.joined(separator: " "))
        }
        return accesses
    }

    private static func toolPart(in payload: [String: Any]) -> [String: Any]? {
        let data = payload["data"] as? [String: Any] ?? payload
        let part = data["part"] as? [String: Any] ?? data
        return part["type"] as? String == "tool" ? part : nil
    }

    private static func toolState(in payload: [String: Any]) -> [String: Any]? {
        toolPart(in: payload)?["state"] as? [String: Any]
    }

    private static func toolName(in payload: [String: Any]) -> String? {
        toolPart(in: payload)?["tool"] as? String
    }

    /// Whether the tool call demonstrably reached none of the protected
    /// `references` it named.
    ///
    /// A file tool that errored read or wrote nothing. A shell command is
    /// judged on what it printed rather than on its exit status, which says
    /// only that the shell ran and reads 0 when a refusal is piped into
    /// another command: it counts as refused when every line it printed is a
    /// refusal naming every protected path it used, or when it failed and
    /// printed nothing at all. A command refused one path can have printed, or
    /// silently copied, another.
    private static func wasRefused(
        _ state: [String: Any],
        tool: String?,
        references: Set<String>,
        strippingOwnPaths ownPaths: [String]
    ) -> Bool {
        let metadata = state["metadata"] as? [String: Any]
        let output = state["output"] as? String ?? metadata?["output"] as? String ?? ""
        let status = state["status"] as? String

        // The tool could not even start. OpenCode reports failures such as an
        // invalid working directory here without a process exit code; no
        // protected path was opened and no command ran.
        if status == "error" && output.isEmpty { return true }

        guard tool == "bash" else {
            // Search tools report an empty result as a successful tool call.
            // That is the file-tool equivalent of `find` printing nothing,
            // not proof that protected material was disclosed.
            if ["glob", "grep"].contains(tool),
               output.trimmingCharacters(in: .whitespacesAndNewlines) == "No files found" {
                return true
            }
            return status == "error"
        }
        var command = (state["input"] as? [String: Any])?["command"] as? String ?? ""
        for path in ownPaths { command = command.replacingOccurrences(of: path, with: "") }
        let lines = output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        // A command that failed and printed nothing obtained nothing — that is
        // a refusal whose message the agent sent to /dev/null. Exit status only
        // means anything here: a refusal piped into `head` exits 0.
        if lines.isEmpty {
            return (metadata?["exit"] as? Int).map { $0 != 0 } ?? false
        }
        let refusals = lines.filter(isRefusal)
        let disclosed = lines.filter { !isRefusal($0) && !isEmptyListingTotal($0) }
        // Copying out of a protected path takes its contents whether or not
        // the command says a word.
        if references.contains(where: { copiesOut($0, in: command) }) { return false }
        // Nothing came back. A command that printed only refusals, or nothing
        // at all, reached nothing: the sandbox is what stopped it, and an
        // agent can silence the refusal but not conjure the content.
        if disclosed.isEmpty { return true }
        // Something came back. A path the command only searched under is clear
        // when none of that output names it; anything else counts unless its
        // refusal is there in the output.
        return references.allSatisfy { reference in
            if refusals.contains(where: { $0.contains(reference) }) { return true }
            return searchesFor(reference, in: command)
                && !disclosed.contains { $0.contains(reference) }
        }
    }

    /// Verbs that take a copy of what they read, so their silence proves
    /// nothing: the contents went somewhere the agent can read later.
    private static let copyCommands: Set<String> = ["cp", "mv", "rsync", "ditto", "tee", "install"]

    /// Whether `command` copies `reference` somewhere rather than just reading it.
    private static func copiesOut(_ reference: String, in command: String) -> Bool {
        let segments = command
            .replacingOccurrences(of: "&&", with: ";")
            .replacingOccurrences(of: "||", with: ";")
            .split(whereSeparator: { $0 == ";" || $0 == "|" || $0 == "\n" })
        return segments.filter { $0.contains(reference) }.contains { segment in
            // `2>/dev/null` and `2>&1` send the refusal away, not the contents.
            let withoutErrorRedirects = segment
                .replacingOccurrences(of: "2>&1", with: "")
                .replacingOccurrences(of: "2>", with: "")
            if withoutErrorRedirects.contains(">") { return true }
            guard let verb = segment.split(whereSeparator: \.isWhitespace).first else { return false }
            return copyCommands.contains(String(verb).split(separator: "/").last.map(String.init) ?? "")
        }
    }

    /// Commands that walk a directory: they name a path to look under and
    /// print only what they find, so a silent one reached nothing.
    private static let searchCommands: Set<String> = ["find", "ls", "fd", "tree", "locate", "du", "stat"]

    /// Whether `reference` appears in `command` only as somewhere to search.
    private static func searchesFor(_ reference: String, in command: String) -> Bool {
        let segments = command
            .replacingOccurrences(of: "&&", with: ";")
            .replacingOccurrences(of: "||", with: ";")
            .split(whereSeparator: { $0 == ";" || $0 == "|" || $0 == "\n" })
        let naming = segments.filter { $0.contains(reference) }
        guard !naming.isEmpty else { return false }
        return naming.allSatisfy { segment in
            guard let verb = segment.split(whereSeparator: \.isWhitespace).first else { return false }
            return searchCommands.contains(String(verb).split(separator: "/").last.map(String.init) ?? "")
        }
    }

    private static func isRefusal(_ line: String) -> Bool {
        line.hasSuffix("Operation not permitted") || line.hasSuffix("Permission denied")
    }

    /// `ls` prints `total 0` after refusing to list a directory.
    private static func isEmptyListingTotal(_ line: String) -> Bool {
        line == "total 0"
    }

    /// Text a write or edit puts into a file is source, not an access. A UI
    /// test that spells out where its own snapshot lands names the harness
    /// root without reading anything; the file the tool targets still counts.
    private static let writtenContentKeys: Set<String> = ["content", "oldString", "newString"]

    private static func withoutWrittenContent(_ input: Any) -> Any {
        guard let object = input as? [String: Any] else { return input }
        return object.filter { !writtenContentKeys.contains($0.key) }
    }

    private static func strings(in value: Any) -> [String] {
        if let string = value as? String { return [string] }
        if let array = value as? [Any] { return array.flatMap(Self.strings) }
        if let object = value as? [String: Any] { return object.values.flatMap(Self.strings) }
        return []
    }

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
        wrappersUsed(in: commands.map { ($0, "") })
    }

    /// Outputs that mean the named program never ran at all.
    ///
    /// The shell could not find it, or the sandbox refused to execute it.
    /// Either way nothing was wrapped; failing a task for a name it typed
    /// would punish the attempt rather than the shortcut.
    static func neverRan(_ output: String) -> Bool {
        let text = output.lowercased()
        return text.contains("command not found")
            || text.contains("execvp() of")
            || text.contains("no such file or directory")
            || (text.contains("operation not permitted") && text.contains("posix_spawn"))
    }

    static func wrappersUsed(in commands: [(command: String, output: String)]) -> [String] {
        var found: Set<String> = []
        for (command, output) in commands {
            guard !neverRan(output) else { continue }
            for segment in command.split(whereSeparator: { "|;&\n".contains($0) }) {
                let text = String(segment)
                if let name = invokedName(in: text),
                   AgentSandbox.distinctiveWrapperNames.contains(name),
                   !isUnsuccessfulAvailabilityProbe(text, name: name, output: output) {
                    found.insert(name)
                }
            }
        }
        return found.sorted()
    }

    private static func isUnsuccessfulAvailabilityProbe(
        _ command: String,
        name: String,
        output: String
    ) -> Bool {
        let words = command.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard words.count >= 3,
              words[0] == "command",
              ["-v", "-V"].contains(words[1])
        else { return false }
        return !output.split(whereSeparator: { $0.isWhitespace }).contains { token in
            token.split(separator: "/").last.map(String.init) == name
        }
    }

    /// The agent's shell commands paired with what they printed.
    static func commandsWithOutput(in log: String) -> [(command: String, output: String)] {
        var found: [(String, String)] = []
        for line in log.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  event["type"] as? String == "agent_event",
                  let payload = event["payload"] as? [String: Any],
                  let command = Self.shellCommand(in: payload)
            else { continue }
            let data2 = payload["data"] as? [String: Any] ?? payload
            let part = data2["part"] as? [String: Any] ?? data2
            let state = part["state"] as? [String: Any] ?? [:]
            let output = (state["output"] as? String)
                ?? ((state["metadata"] as? [String: Any])?["output"] as? String) ?? ""
            found.append((command, output))
        }
        return found
    }

    /// Where a program is Apple's, whatever it is called.
    static let appleToolRoots = ["/Applications/Xcode", "/Library/Developer",
                                 "/usr/bin/", "/bin/", "/usr/libexec/", "/System/"]

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
                // A tool inside Xcode or the system toolchain is Apple's, even
                // when it shares a name with a third-party one. M3 ran Xcode's
                // own xcbuild by full path and was failed for using a wrapper.
                if first.hasPrefix("/") && Self.appleToolRoots.contains(where: first.hasPrefix) {
                    return nil
                }
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
