import Foundation

/// An independent verification step executed after the agent exits.
///
/// Graders run fresh invocations of the relevant tooling; nothing the agent
/// did during its run (builds, test passes, claims of success) carries over.
public protocol Grader: Sendable {
    var identifier: String { get }

    func grade(
        task: BenchmarkTask,
        context: GradingContext
    ) async throws -> GradingResult
}

/// Everything a grader may consult. Grading happens strictly against the
/// final workspace state.
public struct GradingContext: Sendable {
    public let runID: String
    public let workspaceURL: URL
    public let runDirectoryURL: URL
    /// Directory graders should write evidence artifacts into.
    public let artifactsDirectoryURL: URL
    /// Fresh derived data location so agent build state can never leak in.
    public let derivedDataURL: URL
    /// UDID of the simulator provisioned for this run, when the task needs one.
    public let simulatorUDID: String?
    /// Explicit `-destination` derived from the task configuration, if any.
    public let destination: String?
    /// The diff produced by the agent, for change-based assertions.
    public let changedFiles: [String]
    public let processRunner: any ProcessRunning
    public let recorder: EventRecorder

    public init(
        runID: String,
        workspaceURL: URL,
        runDirectoryURL: URL,
        artifactsDirectoryURL: URL,
        derivedDataURL: URL,
        simulatorUDID: String?,
        destination: String?,
        changedFiles: [String],
        processRunner: any ProcessRunning,
        recorder: EventRecorder
    ) {
        self.runID = runID
        self.workspaceURL = workspaceURL
        self.runDirectoryURL = runDirectoryURL
        self.artifactsDirectoryURL = artifactsDirectoryURL
        self.derivedDataURL = derivedDataURL
        self.simulatorUDID = simulatorUDID
        self.destination = destination
        self.changedFiles = changedFiles
        self.processRunner = processRunner
        self.recorder = recorder
    }

    /// Runs a command, recording start/finish events and honoring grader
    /// timeouts, so every grading command lands in the trajectory.
    public func runRecorded(
        _ command: ProcessCommand,
        timeout: Duration? = nil
    ) async throws -> ProcessExecutionResult {
        await recorder.record(.commandStarted, payload: .object([
            "command": .string(command.displayString)
        ]))
        let result = try await processRunner.run(command, timeout: timeout, outputHandler: nil)
        var payload: [String: JSONValue] = [
            "command": .string(command.displayString),
            "duration_ms": .int(Int(result.duration.milliseconds)),
        ]
        if let code = result.exitCode { payload["exit_code"] = .int(Int(code)) }
        if let signal = result.terminationSignal { payload["signal"] = .int(Int(signal)) }
        if result.timedOut { payload["timed_out"] = .bool(true) }
        await recorder.record(.commandFinished, payload: .object(payload))
        return result
    }
}

extension Duration {
    public var milliseconds: Int64 {
        components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000
    }

    public var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
