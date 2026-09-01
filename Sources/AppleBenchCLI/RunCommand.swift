import AppleBenchCore
import ArgumentParser
import Foundation

/// Executes one task end-to-end: agent phase, then independent grading.
struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run a single benchmark task with the given agent."
    )

    @Argument(help: "Task id or path to a task YAML file.")
    var task: String

    @Option(name: .long, help: "Agent harness: opencode (default) or fake (pipeline smoke test).")
    var agent: String = "opencode"

    @Option(name: .long, help: "Model identifier passed to the agent, e.g. anthropic/claude-sonnet-5.")
    var model: String?

    @Option(name: .long, help: "Reasoning effort passed to the agent when its CLI supports it (e.g. low, medium, high).")
    var effort: String?

    @Option(name: .long, help: "Stop the task once it has spent this many tokens. Tightens the task's own budget, never loosens it.")
    var maxTokens: Int?

    @Option(name: .long, help: "Ceiling on the task's wall-clock timeout, in seconds (default: 1200). Tightens, never loosens.")
    var timeoutCap: Int?

    @Option(name: .long, help: "Tart image to run the agent in (isolated VM, no internet). Omit to run locally.")
    var vm: String?

    @Option(name: .long, parsing: .singleValue, help: "CIDR the VM may reach (repeatable); default denies all egress.")
    var vmAllow: [String] = []

    @Option(name: .long, help: "SSH user for the VM image.")
    var vmUser: String = "admin"

    @Option(name: .long, help: "SSH password for the VM image.")
    var vmPassword: String = "admin"

    @Option(name: .long, help: "Directory to resolve bare task ids in.")
    var tasksDir: String?

    @Option(name: .long, help: "Path to a separate evaluation YAML supplying the graders.")
    var evaluation: String?

    @Flag(name: .long, help: "Preserve the run workspace instead of deleting it.")
    var keepWorkspace = false

    @Option(name: .long, help: "Root directory for run artifacts (default: .applebench/runs).")
    var runsDir: String?

    @Option(name: .long, parsing: .singleValue, help: "Extra argument forwarded verbatim to the agent CLI (repeatable).")
    var agentArg: [String] = []

    @Option(name: .long, parsing: .singleValue, help: "Environment variable name to expose to the agent process (repeatable).")
    var allowEnv: [String] = []

    @Flag(name: .customLong("strip-wrapper-clis"), help: "Strip well-known Apple-toolchain wrapper CLIs (flowdeck, tuist, fastlane, xcbeautify, swiftlint, periphery, xcodegen) from the agent's PATH. Use for calibration runs that want to measure raw-toolchain skill, not wrapper-recall.")
    var stripWrapperCLIs = false

    func run() async throws {
        // Line-buffer stdout so progress streams to pipes/CI, not just TTYs.
        setlinebuf(stdout)

        let taskURL = try ReferenceResolver.resolveTask(task, tasksDirectory: tasksDir)
        let benchmarkTask = try TaskLoader.loadTask(
            from: taskURL,
            evaluation: evaluation.map { URL(fileURLWithPath: $0) }
        )
        let adapter = try Wiring.makeAdapter(
            agent: agent,
            model: model,
            effort: effort,
            agentArguments: agentArg,
            vm: vm.map { Wiring.VMOptions(image: $0, allowedCIDRs: vmAllow, sshUser: vmUser, sshPassword: vmPassword) }
        )
        let runner = Wiring.makeRunner()
        let options = RunnerOptions(
            model: model,
            effort: effort,
            keepWorkspace: keepWorkspace,
            environmentAllowlist: allowEnv,
            stripWrapperCLIs: stripWrapperCLIs,
            runsRoot: runsDir.map { URL(fileURLWithPath: $0) } ?? Wiring.defaultRunsRoot(),
            limitCaps: LimitCaps(timeoutSeconds: timeoutCap ?? LimitCaps.standard.timeoutSeconds, maxTokens: maxTokens)
        )

        print("AppleBench · \(benchmarkTask.id)\n")

        let result: BenchmarkRunResult
        do {
            result = try await runner.run(task: benchmarkTask, adapter: adapter, options: options) { progress in
                Self.render(progress, task: benchmarkTask, agent: agent, model: model)
            }
        } catch let failure as BenchmarkFailure {
            // Exit 2: the benchmark could not run credibly (infrastructure),
            // as opposed to exit 1 for a legitimate FAIL verdict.
            FileHandle.standardError.write(Data("error: \(failure)\n".utf8))
            throw ExitCode(2)
        }

        print("")
        print("\(Format.passFail(result.result.passed)) · \(Format.duration(result.result.durationSeconds))")
        if result.result.agentTermination != .completed {
            print("Agent termination: \(result.result.agentTermination.rawValue)")
        }
        print("\nResults:")
        print(options.runsRoot.appendingPathComponent(result.runID).path)
        if !result.result.passed {
            throw ExitCode.failure
        }
    }



    private static func render(_ progress: RunProgress, task: BenchmarkTask, agent: String, model: String?) {
        switch progress {
        case .environmentValidated(let snapshot):
            print("Environment")
            print("  Xcode \(snapshot.xcodeVersion)")
            if let simulator = task.environment.simulator {
                print("  \(simulator.runtime) · \(simulator.device)")
            }
            print("")
            print("Agent")
            print("  \(agent)\(model.map { " · \($0)" } ?? "")")
            print("")
        case .workspacePrepared:
            break
        case .agentStarted:
            print("Running agent...")
        case .agentFinished(let reason, let duration):
            let suffix = reason == .completed ? "" : " (\(reason.rawValue))"
            print("  \(Format.duration(duration.seconds))\(suffix)")
            print("")
        case .gradingStarted:
            print("Grading")
        case .graderFinished(let result):
            let name = Format.pad(result.grader, 12)
            print("  \(name)\(Format.passFail(result.passed))   \(Format.duration(result.duration.seconds))")
        case .finished:
            break
        }
    }
}
