import AppleBenchCore
import ArgumentParser
import Foundation

/// Runs every task in a suite for one or more agents, sequentially, and
/// prints aggregate completion metrics.
struct SuiteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "suite",
        abstract: "Run a suite of tasks for one or more agents and aggregate the results."
    )

    @Argument(help: "Suite id or path to a suite YAML file.")
    var suite: String

    @Option(name: .long, help: "Agent harness: opencode (default) or fake (pipeline smoke test).")
    var agent: String = "opencode"

    @Option(name: .long, help: "Single model identifier passed to the agent.")
    var model: String?

    @Option(name: .long, help: "Comma-separated models to compare through the same harness (e.g. anthropic/claude-sonnet-5,openai/gpt-5).")
    var models: String?

    @Option(name: .long, help: "Reasoning effort passed to the agent when its CLI supports it.")
    var effort: String?

    @Option(name: .long, help: "Write a readable transcript per task under this directory, one folder per model (default: Transcripts).")
    var transcripts: String?

    @Flag(name: .long, help: "Do not write transcripts.")
    var noTranscripts = false

    /// Where transcripts go, or nil when they are switched off.
    var transcriptsRoot: URL? {
        noTranscripts ? nil : URL(fileURLWithPath: transcripts ?? "Transcripts")
    }

    @Flag(name: .long, help: "Seal the agent away from reference solutions, task files, other runs, and any executable outside the Apple toolchain. On for scoring runs.")
    var sealAnswers = false

    @Flag(name: .long, help: "Show what the run is doing as it happens: commands, file edits, graders.")
    var stream = false

    @Flag(name: .long, help: "Show the model's own messages too. Implies --stream, and is much noisier.")
    var streamOutput = false

    /// The live log for this run, off unless asked for.
    var liveLog: LiveEventLog {
        LiveEventLog(level: streamOutput ? .output : (stream ? .activity : .off))
    }

    @Option(name: .long, help: "Stop a task once it has spent this many tokens. Tightens each task's own budget, never loosens it.")
    var maxTokens: Int?

    @Option(name: .long, help: "Ceiling on every task's wall-clock timeout, in seconds (default: 1200). Tightens, never loosens.")
    var timeoutCap: Int?

    @Option(name: .long, help: "Tart image to run the agents in (isolated VM, no internet). Omit to run locally.")
    var vm: String?

    @Option(name: .long, parsing: .singleValue, help: "CIDR the VM may reach (repeatable); default denies all egress.")
    var vmAllow: [String] = []

    @Option(name: .long, help: "SSH user for the VM image.")
    var vmUser: String = "admin"

    @Option(name: .long, help: "SSH password for the VM image.")
    var vmPassword: String = "admin"

    @Option(name: .long, help: "Repetitions per task per agent.")
    var runs: Int = 1

    @Option(name: .long, help: "Directory to resolve task ids in (default: conventional locations).")
    var tasksDir: String?

    @Option(name: .long, help: "Directory containing split evaluation files, laid out as <id>/evaluation.yaml or <id>.yaml.")
    var evaluationsDir: String?

    @Flag(name: .long, help: "Preserve run workspaces instead of deleting them.")
    var keepWorkspace = false

    @Option(name: .long, help: "Root directory for run artifacts (default: .applebench/runs).")
    var runsDir: String?

    @Option(name: .long, parsing: .singleValue, help: "Extra argument forwarded verbatim to the agent CLIs (repeatable).")
    var agentArg: [String] = []

    @Option(name: .long, parsing: .singleValue, help: "Environment variable name to expose to agent processes (repeatable).")
    var allowEnv: [String] = []

    @Flag(name: .customLong("strip-wrapper-clis"), help: "Strip well-known Apple-toolchain wrapper CLIs from the agent's PATH. Use for calibration runs.")
    var stripWrapperCLIs = false

    @Option(name: .long, help: "Maximum concurrent tasks per agent. Defaults to 1 (serial); 2–3 is typical for calibration. Each slot runs a full task with its own simulator, so 3 means up to 3 simulators at once.")
    var parallel: Int = 1

    func run() async throws {
        // Line-buffer stdout so progress streams to pipes/CI, not just TTYs.
        setlinebuf(stdout)
        let modelList = (models?.split(separator: ",").map(String.init) ?? [])
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard models == nil || !modelList.isEmpty else {
            throw ValidationError("--models must contain at least one model")
        }
        guard model == nil || modelList.isEmpty else {
            throw ValidationError("Use either --model or --models, not both")
        }
        guard runs >= 1 else {
            throw ValidationError("--runs must be at least 1")
        }
        guard parallel >= 1 else {
            throw ValidationError("--parallel must be at least 1")
        }

        let suiteURL = try ReferenceResolver.resolveSuite(suite)
        let benchmarkSuite = try TaskLoader.loadSuite(from: suiteURL)

        // Resolve task ids relative to the suite file's surroundings first,
        // then conventional directories.
        let suiteDirectory = suiteURL.deletingLastPathComponent()
        let siblingTasks = suiteDirectory.deletingLastPathComponent().appendingPathComponent("Tasks").path
        var tasks: [BenchmarkTask] = []
        for taskID in benchmarkSuite.tasks {
            let taskURL = try ReferenceResolver.resolveTask(
                taskID,
                tasksDirectory: tasksDir ?? (FileManager.default.fileExists(atPath: siblingTasks) ? siblingTasks : nil)
            )
            let evaluationURL = ReferenceResolver.resolveEvaluation(taskID: taskID, evaluationsDirectory: evaluationsDir)
            tasks.append(try TaskLoader.loadTask(from: taskURL, evaluation: evaluationURL))
        }

        let vmOptions = vm.map {
            Wiring.VMOptions(image: $0, allowedCIDRs: vmAllow, sshUser: vmUser, sshPassword: vmPassword)
        }
        let entries: [RunCoordinator.Entry] = try {
            if modelList.isEmpty {
                return [RunCoordinator.Entry(
                    adapter: try Wiring.makeAdapter(
                        agent: agent, model: model, effort: effort, agentArguments: agentArg, vm: vmOptions
                    ),
                    model: model,
                    effort: effort
                )]
            }
            return try modelList.map { entryModel in
                RunCoordinator.Entry(
                    adapter: try Wiring.makeAdapter(
                        agent: agent, model: entryModel, effort: effort, agentArguments: agentArg, vm: vmOptions
                    ),
                    model: entryModel,
                    effort: effort
                )
            }
        }()
        let coordinator = RunCoordinator(runner: Wiring.makeRunner())
        let options = RunnerOptions(
            model: model,
            effort: effort,
            keepWorkspace: keepWorkspace,
            environmentAllowlist: allowEnv,
            stripWrapperCLIs: stripWrapperCLIs,
            runsRoot: runsDir.map { URL(fileURLWithPath: $0) } ?? Wiring.defaultRunsRoot(),
            limitCaps: LimitCaps(timeoutSeconds: timeoutCap ?? LimitCaps.standard.timeoutSeconds, maxTokens: maxTokens),
            eventObserver: liveLog.observer(),
            sealAnswers: sealAnswers,
            taskSetRoot: ProcessInfo.processInfo.environment["APPLEBENCH_TASKSET"]
                .map { URL(fileURLWithPath: $0) },
            transcriptsRoot: transcriptsRoot
        )

        print("AppleBench · suite \(benchmarkSuite.id) · \(tasks.count) task(s) × \(entries.count) configuration(s) × \(runs) run(s)\n")

        let report = await coordinator.runSuite(
            suite: benchmarkSuite,
            tasks: tasks,
            entries: entries,
            runs: runs,
            options: options,
            parallelism: parallel
        ) { progress in
            switch progress {
            case .taskStarted(let task, let agent, let run, let totalRuns):
                let attempt = totalRuns > 1 ? " (\(run)/\(totalRuns))" : ""
                print("→ \(task) · \(agent)\(attempt)")
            case .taskFinished(let result):
                print("  \(Format.passFail(result.result.passed)) · \(Format.duration(result.result.durationSeconds))")
            case .taskErrored(_, _, let error):
                print("  ERROR · \(error)")
            }
        }

        print("")
        if report.agents.count == 1, let agentReport = report.agents.first {
            print(agentReport.agent)
            print("")
            print("Tasks        \(agentReport.attempted)")
            print("Passed       \(agentReport.passed)")
            print("Failed       \(agentReport.failed)")
            if agentReport.errored > 0 {
                print("Errored      \(agentReport.errored) (infrastructure, excluded from completion)")
            }
            print("Completion   \(Format.percent(agentReport.completionRate))")
            if let median = agentReport.medianDurationSeconds {
                print("Median time  \(Format.duration(median))")
            }
            if let tokens = agentReport.totalTokens {
                print("Tokens       \(tokens)")
            }
            if let cost = agentReport.totalCostUSD {
                print("Cost         \(Format.cost(cost))")
            }
            if let perSolve = agentReport.costPerSolvedTaskUSD {
                print("Cost/solve   \(Format.cost(perSolve))")
            }
        } else {
            let nameWidth = max(12, (report.agents.map(\.agent.count).max() ?? 0) + 2)
            print("\(Format.pad("", nameWidth))\(Format.pad("Passed", 9))\(Format.pad("Completion", 12))\(Format.pad("Median", 9))\(Format.pad("Tokens", 10))\(Format.pad("Cost", 10))Cost/solve")
            for agentReport in report.agents {
                let passed = "\(agentReport.passed)/\(agentReport.attempted)"
                let median = agentReport.medianDurationSeconds.map(Format.duration) ?? "-"
                let tokens = agentReport.totalTokens.map(String.init) ?? "-"
                let cost = agentReport.totalCostUSD.map(Format.cost) ?? "-"
                let perSolve = agentReport.costPerSolvedTaskUSD.map(Format.cost) ?? "-"
                print(
                    Format.pad(agentReport.agent, nameWidth)
                    + Format.pad(passed, 9)
                    + Format.pad(Format.percent(agentReport.completionRate), 12)
                    + Format.pad(median, 9)
                    + Format.pad(tokens, 10)
                    + Format.pad(cost, 10)
                    + perSolve
                )
            }
        }

        if report.agents.contains(where: { $0.errored > 0 }) {
            throw ExitCode.failure
        }
    }
}
