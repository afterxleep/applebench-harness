import AppleBenchCore
import Foundation

/// Applies a fixture's reference solution and exits.
///
/// This is not a benchmark result and never appears in a comparison: it exists
/// so the harness can prove the other half of a fixture's contract. A fixture
/// is only meaningful if it FAILs with an agent that changes nothing and
/// PASSes with the known fix — `Scripts/verify-fixtures.sh` runs both.
///
/// The patch lives outside the agent's checkout, under
/// `.applebench/solutions/<Fixture>.patch`, so the solution is never visible
/// to a real agent working in the workspace.
public struct SolutionAgentAdapter: AgentAdapter {
    public let identifier = "solution"
    public let telemetry = AgentTelemetryCapability.plainText

    /// Directory holding `<Fixture>.patch` files. Defaults to
    /// `.applebench/solutions` beneath the current working directory, matching
    /// where `Scripts/prepare-fixtures.sh` writes them.
    private let solutionsDirectory: URL
    private let processRunner: any ProcessRunning

    public init(
        solutionsDirectory: URL? = nil,
        processRunner: any ProcessRunning = ProcessRunner()
    ) {
        self.solutionsDirectory = solutionsDirectory
            ?? ProcessInfo.processInfo.environment["APPLEBENCH_SOLUTIONS_DIR"].map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".applebench/solutions", isDirectory: true)
        self.processRunner = processRunner
    }

    public func prepare(context: RunContext) async throws {}

    public func run(
        task: BenchmarkTask,
        context: RunContext,
        recorder: EventRecorder
    ) async throws -> AgentRunResult {
        let fixture = Self.fixtureName(for: task)
        let patchURL = solutionsDirectory.appendingPathComponent("\(fixture).patch")

        guard FileManager.default.fileExists(atPath: patchURL.path) else {
            // A fixture with no reference solution cannot be proven solvable;
            // that is an authoring defect, not a benchmark FAIL.
            throw BenchmarkFailure.agentLaunchFailure(
                "No reference solution for fixture '\(fixture)' at \(patchURL.path). "
                + "Run ./Scripts/prepare-fixtures.sh, and check Fixtures/\(fixture)/solution.patch exists."
            )
        }

        await recorder.record(.agentOutput, payload: .object([
            "stream": .string("stdout"),
            "text": .string("solution agent: applying \(patchURL.lastPathComponent)"),
        ]))

        let command = ProcessCommand(
            executable: "/usr/bin/git",
            arguments: ["apply", "--verbose", "--whitespace=nowarn", patchURL.path],
            workingDirectory: context.workspaceURL
        )
        await recorder.record(.commandStarted, payload: .object(["command": .string(command.displayString)]))

        let result: ProcessExecutionResult
        do {
            result = try await processRunner.run(command, timeout: .seconds(120), outputHandler: nil)
        } catch {
            throw BenchmarkFailure.agentLaunchFailure("git apply could not be launched: \(error)")
        }

        var payload: [String: JSONValue] = ["command": .string(command.displayString)]
        if let code = result.exitCode { payload["exit_code"] = .int(Int(code)) }
        await recorder.record(.commandFinished, payload: .object(payload))

        let output = (result.standardOutput + result.standardError)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !output.isEmpty {
            await recorder.record(.agentOutput, payload: .object([
                "stream": .string("stderr"),
                "text": .string(output),
            ]))
        }

        guard result.exitCode == 0 else {
            // A patch that no longer applies means the fixture and its recorded
            // solution have drifted apart. Fail loudly rather than grading a
            // workspace the solution never touched.
            throw BenchmarkFailure.agentLaunchFailure(
                "git apply failed for fixture '\(fixture)' (exit \(result.exitCode.map(String.init) ?? "signal")): \(output)"
            )
        }

        return AgentRunResult(
            metadata: AgentMetadata(
                agent: identifier,
                model: nil,
                version: "1",
                configuration: ["patch": patchURL.lastPathComponent]
            ),
            terminationReason: .completed,
            exitCode: 0,
            finalResponse: "Applied the reference solution for \(fixture)."
        )
    }

    public func cleanup(context: RunContext) async {}

    /// A task's fixture is the last path component of its repository, which is
    /// how `prepare-fixtures.sh` lays snapshots out
    /// (`./.applebench/fixtures/<Fixture>`).
    static func fixtureName(for task: BenchmarkTask) -> String {
        var url = task.repository.url
        while url.hasSuffix("/") { url.removeLast() }
        let name = (url as NSString).lastPathComponent
        return name.hasSuffix(".git") ? String(name.dropLast(4)) : name
    }
}
