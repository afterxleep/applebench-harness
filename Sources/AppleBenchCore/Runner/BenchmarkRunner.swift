import Foundation

/// Options for a single benchmark run.
public struct RunnerOptions: Sendable {
    public var model: String?
    /// Reasoning effort requested for the agent, when its CLI supports it.
    public var effort: String?
    public var keepWorkspace: Bool
    public var environmentAllowlist: [String]
    /// When true, well-known Apple-toolchain wrapper CLIs (flowdeck,
    /// tuist, fastlane, xcbeautify, swiftlint, periphery, xcodegen)
    /// are stripped from the agent's `PATH` before the run starts.
    /// Use this for calibration runs that want to measure
    /// raw-toolchain skill, not
    /// wrapper-recall. Default `false` so day-to-day runs keep the
    /// agent's full toolset.
    public var stripWrapperCLIs: Bool
    /// Root directory beneath which run directories are created.
    public var runsRoot: URL
    /// Ceilings applied to every task's own limits. Tightening only.
    public var limitCaps: LimitCaps
    /// Called for each recorded event, for a caller that wants to show the run
    /// moving. Purely observational: the run behaves identically without it.
    public var eventObserver: (@Sendable (BenchmarkEvent) -> Void)?
    /// Seal the agent away from reference solutions, task files and other
    /// runs. Off by default so a local run against the public samples still
    /// works from any layout; a scoring run should always turn it on.
    public var sealAnswers: Bool = false
    /// Where the task set lives, so the seal can deny it. The runner does not
    /// otherwise need to know.
    public var taskSetRoot: URL?
    /// Where to write a readable transcript per task. `nil` writes none.
    ///
    /// The transcript is a convenience over `events.jsonl`, which already has
    /// everything in it and is unreadable by design.
    public var transcriptsRoot: URL?

    public init(
        model: String? = nil,
        effort: String? = nil,
        keepWorkspace: Bool = false,
        environmentAllowlist: [String] = [],
        stripWrapperCLIs: Bool = false,
        runsRoot: URL,
        limitCaps: LimitCaps = LimitCaps(),
        eventObserver: (@Sendable (BenchmarkEvent) -> Void)? = nil,
        sealAnswers: Bool = false,
        taskSetRoot: URL? = nil,
        transcriptsRoot: URL? = nil
    ) {
        self.model = model
        self.effort = effort
        self.keepWorkspace = keepWorkspace
        self.environmentAllowlist = environmentAllowlist
        self.stripWrapperCLIs = stripWrapperCLIs
        self.runsRoot = runsRoot
        self.limitCaps = limitCaps
        self.eventObserver = eventObserver
        self.sealAnswers = sealAnswers
        self.taskSetRoot = taskSetRoot
        self.transcriptsRoot = transcriptsRoot
    }
}

/// Progress notifications for CLI rendering. Purely observational — the
/// runner's behavior never depends on the observer.
public enum RunProgress: Sendable {
    case environmentValidated(EnvironmentSnapshot)
    case workspacePrepared(URL)
    case agentStarted(agent: String)
    case agentFinished(reason: AgentTerminationReason, duration: Duration)
    case gradingStarted
    case graderFinished(GradingResult)
    case finished(BenchmarkRunResult)
}

/// Orchestrates one complete run: environment validation, workspace
/// preparation, the agent phase, diff capture, independent grading, and
/// result serialization.
public struct BenchmarkRunner: Sendable {
    private let environment: any BenchmarkEnvironment
    private let workspaceManager: WorkspaceManager
    private let simulatorManager: SimulatorManager
    private let processRunner: any ProcessRunning
    private let graderRegistry: GraderRegistry
    private let verificationMaterialiser: VerificationMaterialiser

    /// Extra wall-clock slack granted beyond the task timeout before the
    /// runner forcibly cancels an adapter that failed to enforce the limit
    /// on its own process.
    private let timeoutBackstopSlack: Duration = .seconds(30)

    public init(
        environment: any BenchmarkEnvironment,
        workspaceManager: WorkspaceManager,
        simulatorManager: SimulatorManager,
        processRunner: any ProcessRunning,
        graderRegistry: GraderRegistry,
        verificationMaterialiser: VerificationMaterialiser = VerificationMaterialiser()
    ) {
        self.environment = environment
        self.workspaceManager = workspaceManager
        self.simulatorManager = simulatorManager
        self.processRunner = processRunner
        self.graderRegistry = graderRegistry
        self.verificationMaterialiser = verificationMaterialiser
    }

    public func run(
        task: BenchmarkTask,
        adapter: any AgentAdapter,
        options: RunnerOptions,
        progress: @escaping @Sendable (RunProgress) -> Void = { _ in }
    ) async throws -> BenchmarkRunResult {
        guard !task.graders.isEmpty else {
            throw BenchmarkFailure.invalidTask(
                "Task '\(task.id)' has no graders; supply an evaluation file or add graders to the task"
            )
        }

        let overallStart = ContinuousClock.now

        // Phase 1: environment.
        let snapshot = try await environment.snapshot()
        try environment.validate(task: task, against: snapshot)
        progress(.environmentValidated(snapshot))

        // Phase 2: run directory and event stream.
        let layout = RunDirectoryLayout(rootURL: options.runsRoot)
        let (runID, runDirectoryURL) = try layout.createRunDirectory(taskID: task.id, agentID: adapter.identifier)
        let recorder = try EventRecorder(
            runID: runID,
            fileURL: runDirectoryURL.appendingPathComponent("events.jsonl"),
            observer: options.eventObserver
        )
        defer { Task { await recorder.close() } }

        await recorder.record(.runStarted, payload: .object([
            "task": .string(task.id),
            "agent": .string(adapter.identifier),
        ]))
        await recorder.record(.environmentCaptured, payload: .object([
            "macos": .string(snapshot.macosVersion),
            "architecture": .string(snapshot.architecture),
            "xcode": .string(snapshot.xcodeVersion),
            "xcode_build": .string(snapshot.xcodeBuildNumber),
        ]))

        // Phase 3: isolated workspace.
        let workspace = try await workspaceManager.prepareWorkspace(
            repository: task.repository,
            runDirectoryURL: runDirectoryURL
        )
        await recorder.record(.workspaceCreated, payload: .object([
            "path": .string(workspace.workspaceURL.path),
            "base_commit": .string(workspace.baseCommit),
        ]))
        progress(.workspacePrepared(workspace.workspaceURL))

        let context = RunContext(
            runID: runID,
            workspaceURL: workspace.workspaceURL,
            runDirectoryURL: runDirectoryURL,
            logsDirectoryURL: runDirectoryURL.appendingPathComponent("logs", isDirectory: true),
            model: options.model,
            effort: options.effort,
            environmentAllowlist: options.environmentAllowlist,
            stripWrapperCLIs: options.stripWrapperCLIs,
            sandbox: options.sealAnswers
                ? AgentSandbox.standard(
                    harnessRoot: options.runsRoot.deletingLastPathComponent().deletingLastPathComponent(),
                    taskSetRoot: options.taskSetRoot,
                    workspaceURL: workspace.workspaceURL,
                    denyWrapperCLIs: options.stripWrapperCLIs,
                    agentExecutable: adapter.executableURL,
                    runDirectory: runDirectoryURL
                )
                : nil,
            limits: task.limits.capped(by: options.limitCaps),
            environment: snapshot
        )

        var simulatorUDID: String?
        do {
            // Phase 4: agent, under runner-enforced wall clock.
            let agentResult = try await runAgentPhase(
                task: task,
                adapter: adapter,
                context: context,
                recorder: recorder,
                progress: progress
            )

            // Metadata (which includes the task's grader configuration) is
            // deliberately written only after the agent has exited: while the
            // agent runs, nothing in or near its workspace describes how it
            // will be evaluated.
            try writeMetadata(task: task, snapshot: snapshot, options: options, runDirectoryURL: runDirectoryURL)

            // Phase 5: capture what the agent actually changed.
            let diff = try await workspaceManager.captureDiff(workspace: workspace, runDirectoryURL: runDirectoryURL)
            for file in diff.changedFiles {
                await recorder.record(.fileChanged, payload: .object(["path": .string(file)]))
            }
            await recorder.record(.artifactCreated, payload: .object(["path": .string("diff.patch")]))

            // The graded tests go in only now: after the agent's process has
            // exited and after its diff is on disk. Until this line the
            // workspace held an app with no test target, so nothing the agent
            // could read described how it would be judged.
            let verification = try await verificationMaterialiser.materialise(
                fixture: VerificationMaterialiser.fixtureName(for: task),
                into: workspace.workspaceURL,
                processRunner: processRunner
            )
            if !verification.isEmpty {
                await recorder.record(.verificationMaterialised, payload: .object([
                    "fixture": .string(verification.fixture),
                    "paths": .array(verification.paths.map { .string($0) }),
                ]))
            }

            // Phase 6: independent grading against the final workspace state.
            //
            // Grading builds into its own derived data, and it starts empty:
            // a run must be judged on what the agent left behind, never on a
            // build directory carrying anything from before it.
            let derivedData = runDirectoryURL.appendingPathComponent("DerivedData", isDirectory: true)
            try? FileManager.default.removeItem(at: derivedData)

            await recorder.record(.gradingStarted)
            progress(.gradingStarted)

            if task.environment.simulator != nil, taskNeedsSimulator(task) {
                // Recover from whatever ended the last run. A kill, a CI
                // timeout or a crash never reaches teardown, so its device is
                // still here; sweeping before creating ours means a leak
                // survives one run rather than accumulating across a suite.
                let reaped = await simulatorManager.reapStaleDevices()
                if reaped > 0 {
                    await recorder.record(.simulatorReaped, payload: .object([
                        "removed": .int(reaped),
                        "reason": .string("left behind by an earlier run"),
                    ]))
                }
                let udid = try await simulatorManager.createDevice(
                    name: "AppleBench-\(runID)",
                    requirement: task.environment.simulator!,
                    snapshot: snapshot
                )
                simulatorUDID = udid
                await recorder.record(.simulatorPrepared, payload: .object(["udid": .string(udid)]))
                // Booting is only required when something will run on the
                // device; plain builds just need the destination to exist.
                let needsBoot = task.graders.contains { specification in
                    switch specification {
                    case .xcuitest, .runtime, .uiflow, .mutation: true
                    case .build, .xctest, .file, .xcodeproj, .trajectory: false
                    }
                }
                if needsBoot {
                    try await simulatorManager.bootAndWait(udid: udid)
                }
            }

            let gradingContext = GradingContext(
                runID: runID,
                workspaceURL: workspace.workspaceURL,
                runDirectoryURL: runDirectoryURL,
                artifactsDirectoryURL: context.logsDirectoryURL,
                derivedDataURL: runDirectoryURL.appendingPathComponent("DerivedData", isDirectory: true),
                simulatorUDID: simulatorUDID,
                agent: adapter.identifier,
                destination: destination(for: task, snapshot: snapshot, simulatorUDID: simulatorUDID),
                changedFiles: diff.changedFiles,
                processRunner: processRunner,
                recorder: recorder
            )

            var gradingResults: [GradingResult] = []
            for specification in task.graders {
                let grader = try graderRegistry.makeGrader(for: specification)
                await recorder.record(.graderStarted, payload: .object(["grader": .string(grader.identifier)]))
                let result: GradingResult
                do {
                    result = try await grader.grade(task: task, context: gradingContext)
                } catch let failure as BenchmarkFailure {
                    throw failure
                } catch {
                    throw BenchmarkFailure.graderFailure(grader: grader.identifier, message: "\(error)")
                }
                await recorder.record(.graderFinished, payload: .object([
                    "grader": .string(grader.identifier),
                    "passed": .bool(result.passed),
                    "duration_ms": .int(Int(result.duration.milliseconds)),
                    "summary": .string(result.summary),
                ]))
                gradingResults.append(result)
                progress(.graderFinished(result))
            }

            // Phase 7: result.
            let passed = gradingResults.allSatisfy(\.passed)
            let totalDuration = overallStart.duration(to: .now)
            await recorder.record(.runFinished, payload: .object([
                "passed": .bool(passed),
                "duration_ms": .int(Int(totalDuration.milliseconds)),
            ]))

            let events = await recorder.allEvents()
            let result = BenchmarkRunResult(
                runID: runID,
                task: task.id,
                category: task.category,
                difficulty: task.difficulty,
                tags: task.tags,
                agent: agentResult.metadata,
                environment: snapshot.summary(for: task),
                result: .init(
                    passed: passed,
                    durationSeconds: totalDuration.seconds,
                    agentTermination: agentResult.terminationReason
                ),
                usage: agentResult.usage,
                metrics: TrajectoryMetrics(events: events),
                graders: gradingResults.map(BenchmarkRunResult.GraderOutcome.init),
                git: .init(
                    baseCommit: workspace.baseCommit,
                    finalCommit: diff.finalCommit,
                    filesChanged: diff.filesChanged,
                    insertions: diff.insertions,
                    deletions: diff.deletions
                ),
                artifacts: .init(events: "events.jsonl", diff: "diff.patch", logs: "logs")
            )
            try result.write(to: runDirectoryURL.appendingPathComponent("result.json"))

            // Best effort: a transcript that could not be written is a lost
            // convenience, not a lost result. events.jsonl still holds it all.
            if let transcriptsRoot = options.transcriptsRoot {
                do {
                    let url = try RunTranscript.write(
                        task: task, result: result, events: events, root: transcriptsRoot
                    )
                    await recorder.record(.artifactCreated, payload: .object([
                        "path": .string(url.path), "kind": .string("transcript"),
                    ]))
                } catch {
                    await recorder.record(.warning, payload: .object([
                        "message": .string("Could not write the transcript: \(error)")
                    ]))
                }
            }

            await teardown(
                simulatorUDID: simulatorUDID,
                workspace: workspace,
                adapter: adapter,
                context: context,
                keepWorkspace: options.keepWorkspace,
                recorder: recorder
            )
            progress(.finished(result))
            return result
        } catch {
            await teardown(
                simulatorUDID: simulatorUDID,
                workspace: workspace,
                adapter: adapter,
                context: context,
                keepWorkspace: true,  // always keep evidence of a failed run
                recorder: recorder
            )
            throw error
        }
    }

    // MARK: - Agent phase

    private func runAgentPhase(
        task: BenchmarkTask,
        adapter: any AgentAdapter,
        context: RunContext,
        recorder: EventRecorder,
        progress: @escaping @Sendable (RunProgress) -> Void
    ) async throws -> AgentRunResult {
        do {
            try await adapter.prepare(context: context)
        } catch let failure as BenchmarkFailure {
            throw failure
        } catch {
            throw BenchmarkFailure.agentLaunchFailure("\(error)")
        }

        await recorder.record(.agentStarted, payload: .object([
            "agent": .string(adapter.identifier),
            "timeout_seconds": .int(context.limits.timeoutSeconds),
        ]))
        progress(.agentStarted(agent: adapter.identifier))
        let agentStart = ContinuousClock.now

        // Adapters are expected to enforce the timeout on their own process
        // (via ProcessRunner). The runner adds a backstop: if the adapter
        // overruns the limit plus slack, its task is cancelled, which
        // terminates the agent's process group.
        let backstop = Duration.seconds(context.limits.timeoutSeconds) + timeoutBackstopSlack
        let result: AgentRunResult
        do {
            result = try await withThrowingTaskGroup(of: AgentRunResult?.self) { group in
                group.addTask {
                    try await adapter.run(task: task, context: context, recorder: recorder)
                }
                group.addTask {
                    try await Task.sleep(for: backstop)
                    return nil
                }
                defer { group.cancelAll() }
                while let outcome = try await group.next() {
                    if let outcome {
                        return outcome
                    }
                    // Backstop fired first: cancel the adapter and report timeout.
                    group.cancelAll()
                    return AgentRunResult(
                        metadata: AgentMetadata(agent: adapter.identifier, model: context.model),
                        terminationReason: .timeout
                    )
                }
                throw BenchmarkFailure.agentLaunchFailure("Agent task ended without a result")
            }
        } catch let failure as BenchmarkFailure {
            throw failure
        } catch is CancellationError {
            result = AgentRunResult(
                metadata: AgentMetadata(agent: adapter.identifier, model: context.model),
                terminationReason: .cancelled
            )
            return result
        } catch {
            throw BenchmarkFailure.agentLaunchFailure("\(error)")
        }

        let agentDuration = agentStart.duration(to: .now)
        var payload: [String: JSONValue] = [
            "termination": .string(result.terminationReason.rawValue),
            "duration_ms": .int(Int(agentDuration.milliseconds)),
        ]
        if let exitCode = result.exitCode { payload["exit_code"] = .int(Int(exitCode)) }
        await recorder.record(.agentFinished, payload: .object(payload))
        progress(.agentFinished(reason: result.terminationReason, duration: agentDuration))
        return result
    }

    // MARK: - Helpers

    private func taskNeedsSimulator(_ task: BenchmarkTask) -> Bool {
        task.graders.contains { specification in
            switch specification {
            case .xcuitest, .runtime, .uiflow, .mutation: true
            case .build(let configuration): configuration.destination == nil && task.environment.platform == .ios
            case .xctest: task.environment.platform == .ios
            // Resolving build settings for an iOS scheme needs a concrete
            // destination, and product-level assertions build the scheme.
            case .xcodeproj(let configuration): configuration.destination == nil && task.environment.platform == .ios
            case .file, .trajectory: false
            }
        }
    }

    private func destination(
        for task: BenchmarkTask,
        snapshot: EnvironmentSnapshot,
        simulatorUDID: String?
    ) -> String? {
        if let simulatorUDID {
            return "platform=iOS Simulator,id=\(simulatorUDID)"
        }
        switch task.environment.platform {
        case .macos:
            return "platform=macOS"
        case .ios:
            if let simulator = task.environment.simulator,
               let runtime = snapshot.runtime(named: simulator.runtime) {
                // Use the version reported by simctl (e.g. "26.5"), not the
                // display name ("iOS 26.5 Beta") — the destination spec must
                // match a value xcodebuild understands.
                return "platform=iOS Simulator,name=\(simulator.device),OS=\(runtime.version)"
            }
            return "generic/platform=iOS Simulator"
        }
    }

    private func writeMetadata(
        task: BenchmarkTask,
        snapshot: EnvironmentSnapshot,
        options: RunnerOptions,
        runDirectoryURL: URL
    ) throws {
        struct Metadata: Encodable {
            var task: BenchmarkTask
            var environment: EnvironmentSnapshot
            var model: String?
            var effort: String?
            var keepWorkspace: Bool

            enum CodingKeys: String, CodingKey {
                case task, environment, model, effort
                case keepWorkspace = "keep_workspace"
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(Metadata(
            task: task,
            environment: snapshot,
            model: options.model,
            effort: options.effort,
            keepWorkspace: options.keepWorkspace
        ))
        try data.write(to: runDirectoryURL.appendingPathComponent("metadata.json"))
    }

    private func teardown(
        simulatorUDID: String?,
        workspace: WorkspaceManager.Workspace,
        adapter: any AgentAdapter,
        context: RunContext,
        keepWorkspace: Bool,
        recorder: EventRecorder
    ) async {
        if let simulatorUDID {
            await simulatorManager.shutdown(udid: simulatorUDID)
            let removed = await simulatorManager.deleteVerifying(udid: simulatorUDID)
            await recorder.record(.simulatorReaped, payload: .object([
                "udid": .string(simulatorUDID),
                "removed": .bool(removed),
            ]))
        }
        await adapter.cleanup(context: context)
        if !keepWorkspace {
            workspaceManager.removeWorkspace(workspace)

            // Derived data is a build directory, not evidence: the logs, the
            // result bundles, the diff and result.json all survive. A suite of
            // a hundred-odd tasks keeps a hundred-odd copies otherwise, which
            // fills the disk partway through and turns every task after that
            // into a timeout with nothing in the output to say why.
            let derivedData = context.runDirectoryURL.appendingPathComponent("DerivedData", isDirectory: true)
            try? FileManager.default.removeItem(at: derivedData)
        }
    }
}
