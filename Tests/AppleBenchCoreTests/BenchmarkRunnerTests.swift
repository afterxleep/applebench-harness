import Foundation
import Testing
@testable import AppleBenchCore

// MARK: - Fakes

struct FakeEnvironment: BenchmarkEnvironment {
    var failValidation: String?

    func snapshot() async throws -> EnvironmentSnapshot {
        EnvironmentSnapshot(
            macosVersion: "26.5",
            architecture: "arm64",
            xcodePath: "/Applications/Xcode.app/Contents/Developer",
            xcodeVersion: "27.0",
            xcodeBuildNumber: "27A0000"
        )
    }

    func validate(task: BenchmarkTask, against snapshot: EnvironmentSnapshot) throws {
        if let failValidation {
            throw BenchmarkFailure.environmentUnavailable(failValidation)
        }
    }
}

struct FakeGrader: Grader {
    var identifier = "fake-grader"
    var passed = true
    var error: (any Error)?

    func grade(task: BenchmarkTask, context: GradingContext) async throws -> GradingResult {
        if let error { throw error }
        return GradingResult(
            grader: identifier,
            passed: passed,
            duration: .milliseconds(5),
            summary: passed ? "ok" : "not ok"
        )
    }
}

struct ScriptedAdapter: AgentAdapter {
    var identifier = "scripted"
    var telemetry = AgentTelemetryCapability.plainText
    var prepareError: BenchmarkFailure?
    var terminationReason = AgentTerminationReason.completed
    var edit: @Sendable (RunContext) throws -> Void = { _ in }

    func prepare(context: RunContext) async throws {
        if let prepareError { throw prepareError }
    }

    func run(task: BenchmarkTask, context: RunContext, recorder: EventRecorder) async throws -> AgentRunResult {
        try edit(context)
        await recorder.record(.agentOutput, payload: .object(["text": .string("worked")]))
        return AgentRunResult(
            metadata: AgentMetadata(agent: identifier, model: context.model),
            terminationReason: terminationReason,
            exitCode: terminationReason == .completed ? 0 : nil,
            usage: AgentUsage(inputTokens: 10, outputTokens: 20, totalTokens: 30)
        )
    }

    func cleanup(context: RunContext) async {}
}

// MARK: - Harness

struct RunnerHarness {
    let repoURL: URL
    let runsRoot: URL
    let task: BenchmarkTask

    static func make() async throws -> RunnerHarness {
        let runner = ProcessRunner()
        let repoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("applebench-runner-repo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
        try "let a = 1\n".write(to: repoURL.appendingPathComponent("App.swift"), atomically: true, encoding: .utf8)
        for arguments in [["init", "-q"], ["add", "-A"], ["commit", "-qm", "seed"]] {
            let result = try await runner.run(ProcessCommand(
                executable: "/usr/bin/git",
                arguments: arguments,
                workingDirectory: repoURL,
                environment: [
                    "PATH": "/usr/bin:/bin",
                    "GIT_AUTHOR_NAME": "T", "GIT_AUTHOR_EMAIL": "t@t",
                    "GIT_COMMITTER_NAME": "T", "GIT_COMMITTER_EMAIL": "t@t",
                ]
            ))
            precondition(result.exitCode == 0, result.standardError)
        }

        let runsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("applebench-runner-runs-\(UUID().uuidString)", isDirectory: true)

        let task = BenchmarkTask(
            id: "unit-001",
            title: "Unit test task",
            category: .tests,
            difficulty: 2,
            repository: RepositorySpecification(url: repoURL.path, commit: "HEAD"),
            prompt: "Fix it.",
            environment: EnvironmentRequirements(platform: .ios),
            limits: RunLimits(timeoutSeconds: 60),
            graders: [.file(FileGraderConfiguration(assertions: [FileAssertion(path: "App.swift", exists: true)]))],
            tags: ["unit"]
        )
        return RunnerHarness(repoURL: repoURL, runsRoot: runsRoot, task: task)
    }

    func makeRunner(grader: FakeGrader = FakeGrader()) -> BenchmarkRunner {
        var registry = GraderRegistry()
        registry.register { _ in grader }
        return BenchmarkRunner(
            environment: FakeEnvironment(),
            workspaceManager: WorkspaceManager(),
            simulatorManager: SimulatorManager(),
            processRunner: ProcessRunner(),
            graderRegistry: registry
        )
    }

    var options: RunnerOptions {
        RunnerOptions(model: "test-model", keepWorkspace: false, runsRoot: runsRoot)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: repoURL)
        try? FileManager.default.removeItem(at: runsRoot)
    }
}

// MARK: - Tests

@Suite("Benchmark runner orchestration", .serialized)
struct BenchmarkRunnerTests {
    @Test("A full run produces result.json, events.jsonl, and a diff")
    func fullRun() async throws {
        let harness = try await RunnerHarness.make()
        defer { harness.cleanUp() }

        let adapter = ScriptedAdapter(edit: { context in
            try "let a = 2\n".write(
                to: context.workspaceURL.appendingPathComponent("App.swift"),
                atomically: true, encoding: .utf8
            )
        })
        let result = try await harness.makeRunner().run(
            task: harness.task,
            adapter: adapter,
            options: harness.options
        )

        #expect(result.result.passed)
        #expect(result.result.agentTermination == .completed)
        #expect(result.task == "unit-001")
        #expect(result.tags == ["unit"])
        #expect(result.category == .tests)
        #expect(result.difficulty == 2)
        #expect(result.agent.model == "test-model")
        #expect(result.usage.totalTokens == 30)
        #expect(result.git.filesChanged == 1)
        #expect(result.git.insertions == 1)
        #expect(result.git.deletions == 1)
        #expect(result.metrics?.agentOutputChunks == 1)

        let runDirectory = harness.runsRoot.appendingPathComponent(result.runID)
        #expect(FileManager.default.fileExists(atPath: runDirectory.appendingPathComponent("result.json").path))
        #expect(FileManager.default.fileExists(atPath: runDirectory.appendingPathComponent("events.jsonl").path))
        #expect(FileManager.default.fileExists(atPath: runDirectory.appendingPathComponent("diff.patch").path))
        #expect(FileManager.default.fileExists(atPath: runDirectory.appendingPathComponent("metadata.json").path))
        // Workspace removed because keepWorkspace is false.
        #expect(!FileManager.default.fileExists(atPath: runDirectory.appendingPathComponent("workspace").path))

        let onDisk = try BenchmarkRunResult.read(from: runDirectory.appendingPathComponent("result.json"))
        #expect(onDisk == result)
    }

    @Test("Evaluator metadata is not on disk while the agent runs")
    func hermeticAgentPhase() async throws {
        let harness = try await RunnerHarness.make()
        defer { harness.cleanUp() }

        // The scripted "agent" checks its surroundings: nothing in the run
        // directory may describe how the run will be graded.
        let adapter = ScriptedAdapter(edit: { context in
            let metadataPath = context.runDirectoryURL.appendingPathComponent("metadata.json").path
            if FileManager.default.fileExists(atPath: metadataPath) {
                throw BenchmarkFailure.infrastructureFailure("agent can see evaluator metadata")
            }
        })
        let result = try await harness.makeRunner().run(
            task: harness.task,
            adapter: adapter,
            options: harness.options
        )
        #expect(result.result.passed)

        // After the run, metadata exists for reproducibility.
        let metadataURL = harness.runsRoot
            .appendingPathComponent(result.runID)
            .appendingPathComponent("metadata.json")
        #expect(FileManager.default.fileExists(atPath: metadataURL.path))
    }

    @Test("keep-workspace preserves the checkout")
    func keepWorkspace() async throws {
        let harness = try await RunnerHarness.make()
        defer { harness.cleanUp() }

        var options = harness.options
        options.keepWorkspace = true
        let result = try await harness.makeRunner().run(
            task: harness.task,
            adapter: ScriptedAdapter(),
            options: options
        )
        let workspace = harness.runsRoot
            .appendingPathComponent(result.runID)
            .appendingPathComponent("workspace")
        #expect(FileManager.default.fileExists(atPath: workspace.path))
    }

    @Test("A failing grader is a FAIL verdict, not an error")
    func failingGrader() async throws {
        let harness = try await RunnerHarness.make()
        defer { harness.cleanUp() }

        let result = try await harness.makeRunner(grader: FakeGrader(passed: false)).run(
            task: harness.task,
            adapter: ScriptedAdapter(),
            options: harness.options
        )
        #expect(!result.result.passed)
        #expect(result.graders.first?.passed == false)
    }

    @Test("A grader that cannot execute is an infrastructure failure")
    func throwingGrader() async throws {
        let harness = try await RunnerHarness.make()
        defer { harness.cleanUp() }

        struct Boom: Error {}
        await #expect(throws: BenchmarkFailure.self) {
            _ = try await harness.makeRunner(grader: FakeGrader(error: Boom())).run(
                task: harness.task,
                adapter: ScriptedAdapter(),
                options: harness.options
            )
        }
    }

    @Test("Agent timeout is recorded while grading still runs")
    func timeoutStillGrades() async throws {
        let harness = try await RunnerHarness.make()
        defer { harness.cleanUp() }

        let result = try await harness.makeRunner().run(
            task: harness.task,
            adapter: ScriptedAdapter(terminationReason: .timeout),
            options: harness.options
        )
        // Both facts recorded, never collapsed: the agent timed out AND the
        // final workspace passed grading.
        #expect(result.result.agentTermination == .timeout)
        #expect(result.result.passed)
    }

    @Test("Adapter prepare failures surface as agent launch failures")
    func prepareFailure() async throws {
        let harness = try await RunnerHarness.make()
        defer { harness.cleanUp() }

        await #expect(throws: BenchmarkFailure.self) {
            _ = try await harness.makeRunner().run(
                task: harness.task,
                adapter: ScriptedAdapter(prepareError: .agentLaunchFailure("codex not installed")),
                options: harness.options
            )
        }
    }

    @Test("Environment validation failures abort before the agent starts")
    func environmentFailure() async throws {
        let harness = try await RunnerHarness.make()
        defer { harness.cleanUp() }

        var registry = GraderRegistry()
        registry.register { _ in FakeGrader() }
        let runner = BenchmarkRunner(
            environment: FakeEnvironment(failValidation: "Xcode 27.0 required"),
            workspaceManager: WorkspaceManager(),
            simulatorManager: SimulatorManager(),
            processRunner: ProcessRunner(),
            graderRegistry: registry
        )
        await #expect(throws: BenchmarkFailure.self) {
            _ = try await runner.run(
                task: harness.task,
                adapter: ScriptedAdapter(),
                options: harness.options
            )
        }
    }

    @Test("Tasks without graders are rejected at run time")
    func noGraders() async throws {
        let harness = try await RunnerHarness.make()
        defer { harness.cleanUp() }

        var task = harness.task
        task.graders = []
        await #expect(throws: BenchmarkFailure.self) {
            _ = try await harness.makeRunner().run(
                task: task,
                adapter: ScriptedAdapter(),
                options: harness.options
            )
        }
    }
}

@Suite("Suite coordination", .serialized)
struct RunCoordinatorTests {
    @Test("Aggregates completion across repeated runs")
    func aggregation() async throws {
        let harness = try await RunnerHarness.make()
        defer { harness.cleanUp() }

        let coordinator = RunCoordinator(runner: harness.makeRunner())
        let suite = BenchmarkSuite(id: "unit", name: "Unit", tasks: ["unit-001"])
        let report = await coordinator.runSuite(
            suite: suite,
            tasks: [harness.task],
            entries: [.init(adapter: ScriptedAdapter())],
            runs: 2,
            options: harness.options
        )

        #expect(report.agents.count == 1)
        let agent = try #require(report.agents.first)
        #expect(agent.attempted == 2)
        #expect(agent.passed == 2)
        #expect(agent.failed == 0)
        #expect(agent.errored == 0)
        #expect(agent.completionRate == 1.0)
        #expect(agent.medianDurationSeconds != nil)
        // ScriptedAdapter reports 30 tokens per run; raw sums surface them.
        #expect(agent.totalTokens == 60)
        #expect(report.results.count == 2)
    }

    @Test("Infrastructure errors on one agent do not abort the suite")
    func erroringAgent() async throws {
        let harness = try await RunnerHarness.make()
        defer { harness.cleanUp() }

        let coordinator = RunCoordinator(runner: harness.makeRunner())
        let suite = BenchmarkSuite(id: "unit", name: "Unit", tasks: ["unit-001"])
        let broken = ScriptedAdapter(
            identifier: "broken",
            prepareError: .agentLaunchFailure("missing binary")
        )
        let report = await coordinator.runSuite(
            suite: suite,
            tasks: [harness.task],
            entries: [
                .init(adapter: broken, model: "model-a"),
                .init(adapter: ScriptedAdapter(), model: "model-b"),
            ],
            runs: 1,
            options: harness.options
        )

        #expect(report.agents.count == 2)
        #expect(report.agents[0].agent == "broken · model-a")
        #expect(report.agents[0].errored == 1)
        #expect(report.agents[0].attempted == 0)
        #expect(report.agents[1].agent == "scripted · model-b")
        #expect(report.agents[1].passed == 1)
    }

    @Test("Median duration")
    func median() {
        #expect(RunCoordinator.median([]) == nil)
        #expect(RunCoordinator.median([3]) == 3)
        #expect(RunCoordinator.median([1, 9]) == 5)
        #expect(RunCoordinator.median([5, 1, 9]) == 5)
        #expect(RunCoordinator.median([4, 1, 9, 5]) == 4.5)
    }
}
