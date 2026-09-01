import AppleBenchCore
import Foundation
import Testing
@testable import AppleBenchGraders

/// A `ProcessRunning` whose responses are scripted in advance, for graders
/// that would otherwise shell out to `xcodebuild`.
///
/// Recorded commands and queued responses share a lock so concurrent
/// graders under test still see a coherent order. The actor-free
/// `@unchecked Sendable` is acceptable for tests only.
final class FakeProcessRunner: ProcessRunning, @unchecked Sendable {
    struct Response: Sendable {
        var exitCode: Int32
        var standardOutput: String
        var standardError: String
        var duration: Duration
        var timedOut: Bool
    }

    private let lock = NSLock()
    private var recordedCommands: [ProcessCommand] = []
    private var responses: [Response] = []
    /// When non-nil, every `run` returns this response regardless of how
    /// many calls were scripted — useful for "one scripted xcodebuild call,
    /// many validation passes".
    private var universalResponse: Response?

    init() {}

    /// Append a response that will be returned by the *next* `run` call
    /// in FIFO order. After all responses are consumed, further calls
    /// throw — a missing script is a test bug, not a runtime success.
    func enqueue(
        exitCode: Int32 = 0,
        standardOutput: String = "",
        standardError: String = "",
        duration: Duration = .milliseconds(10),
        timedOut: Bool = false
    ) {
        lock.withLock {
            responses.append(Response(
                exitCode: exitCode,
                standardOutput: standardOutput,
                standardError: standardError,
                duration: duration,
                timedOut: timedOut
            ))
        }
    }

    /// Configure this runner so that every `run` returns the same response
    /// until cleared. Useful for graders that do their own internal
    /// subprocess orchestration (e.g. `xcresulttool` after a `xcodebuild`).
    func setUniversal(
        exitCode: Int32 = 0,
        standardOutput: String = "",
        standardError: String = "",
        duration: Duration = .milliseconds(10),
        timedOut: Bool = false
    ) {
        lock.withLock {
            universalResponse = Response(
                exitCode: exitCode,
                standardOutput: standardOutput,
                standardError: standardError,
                duration: duration,
                timedOut: timedOut
            )
        }
    }

    func clearUniversal() {
        lock.withLock { universalResponse = nil }
    }

    /// The commands the grader has invoked so far, in order.
    func commands() -> [ProcessCommand] {
        lock.withLock { recordedCommands }
    }

    func lastCommand() -> ProcessCommand? {
        lock.withLock { recordedCommands.last }
    }

    /// First recorded command matching the predicate. Useful when a grader
    /// makes more than one subprocess call (e.g. `xcodebuild` followed by
    /// `xcrun xcresulttool`) and the test wants the earlier one.
    func firstCommand(where predicate: (ProcessCommand) -> Bool) -> ProcessCommand? {
        lock.withLock { recordedCommands.first(where: predicate) }
    }

    func run(
        _ command: ProcessCommand,
        timeout: Duration?,
        outputHandler: (@Sendable (ProcessOutputStream, String) -> Void)?
    ) async throws -> ProcessExecutionResult {
        let response: Response = lock.withLock {
            recordedCommands.append(command)
            if let universalResponse {
                return universalResponse
            }
            guard !responses.isEmpty else {
                fatalError("FakeProcessRunner received an unexpected call: \(command.displayString)")
            }
            return responses.removeFirst()
        }
        return ProcessExecutionResult(
            exitCode: response.exitCode,
            terminationSignal: nil,
            standardOutput: response.standardOutput,
            standardError: response.standardError,
            duration: response.duration,
            timedOut: response.timedOut
        )
    }
}

/// A minimal `GradingContext` pointing at a temporary workspace and
/// artifacts directory. The event recorder is in-memory; nothing is
/// written to disk.
func makeGradingContext(
    processRunner: any ProcessRunning,
    workspace: URL? = nil,
    derivedData: URL? = nil,
    changedFiles: [String] = []
) async throws -> (GradingContext, URL) {
    let workspaceURL = workspace
        ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("applebench-grader-\(UUID().uuidString)", isDirectory: true)
    if !FileManager.default.fileExists(atPath: workspaceURL.path) {
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
    }
    let context = GradingContext(
        runID: "test",
        workspaceURL: workspaceURL,
        runDirectoryURL: workspaceURL,
        artifactsDirectoryURL: workspaceURL,
        derivedDataURL: derivedData ?? workspaceURL.appendingPathComponent("DerivedData"),
        simulatorUDID: nil,
        destination: "platform=iOS Simulator,name=iPhone 17,OS=26.5",
        changedFiles: changedFiles,
        processRunner: processRunner,
        recorder: try EventRecorder(runID: "test", fileURL: nil)
    )
    return (context, workspaceURL)
}

func defaultTask() -> BenchmarkTask {
    BenchmarkTask(
        id: "t",
        title: "t",
        repository: RepositorySpecification(url: "/tmp", commit: "HEAD"),
        prompt: "p",
        environment: EnvironmentRequirements(platform: .ios)
    )
}
