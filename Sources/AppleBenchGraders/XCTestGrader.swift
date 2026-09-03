import AppleBenchCore
import Foundation

/// Runs unit/integration tests through a fresh `xcodebuild test` invocation
/// and grades on structured `.xcresult` totals. Also used, with a different
/// identifier, for UI tests — the xcodebuild contract is identical.
public struct XCTestGrader: Grader {
    public let identifier: String
    private let configuration: XCTestGraderConfiguration

    public init(configuration: XCTestGraderConfiguration, identifier: String = "xctest") {
        self.identifier = identifier
        self.configuration = configuration
    }

    public func grade(task: BenchmarkTask, context: GradingContext) async throws -> GradingResult {
        let start = ContinuousClock.now

        var arguments = XcodebuildSupport.baseArguments(
            project: configuration.project,
            workspace: configuration.workspace,
            scheme: configuration.scheme,
            configuration: nil,
            destination: configuration.destination,
            context: context
        )
        if let testPlan = configuration.testPlan {
            arguments += ["-testPlan", testPlan]
        }
        for test in configuration.tests {
            arguments.append("-only-testing:\(test)")
        }
        for test in configuration.skipTests {
            arguments.append("-skip-testing:\(test)")
        }
        // Skip the slow sysdiagnose collection that runs after tests; it adds
        // minutes per run and provides nothing the harness uses to grade.
        arguments += ["-collect-test-diagnostics", "never", "test"]

        // Each attempt writes its own result bundle: xcodebuild refuses to
        // start at all when `-resultBundlePath` already exists.
        func attempt(_ suffix: String) async throws -> (ProcessExecutionResult, Artifact, URL) {
            let bundle = XcodebuildSupport.resultBundleURL(named: identifier + suffix, context: context)
            let (result, artifact) = try await XcodebuildSupport.run(
                arguments: arguments + ["-resultBundlePath", bundle.path],
                logName: "\(identifier)\(suffix).log",
                context: context
            )
            return (result, artifact, bundle)
        }

        var (result, logArtifact, resultBundle) = try await attempt("")

        // Installing the app or attaching the runner sometimes fails outright,
        // most often when simulators have been churning through back-to-back UI
        // runs. That is the host having a bad moment, not the agent's work
        // failing, and charging it to the agent turns a benchmark score into a
        // coin flip. One retry costs a couple of minutes and removes the false
        // verdict.
        if Self.isHostFailure(result) {
            await context.recorder.record(.warning, payload: .object([
                "grader": .string(identifier),
                "message": .string("run failed before any test could execute; retrying once before recording a verdict"),
            ]))
            (result, logArtifact, resultBundle) = try await attempt("-retry")
        }

        var evidence = [logArtifact]
        if FileManager.default.fileExists(atPath: resultBundle.path) {
            evidence.append(Artifact(name: resultBundle.lastPathComponent, path: "logs/\(resultBundle.lastPathComponent)"))
        }

        let summaryData = await XcodebuildSupport.testSummary(xcresultURL: resultBundle, context: context)

        let passed: Bool
        let summaryText: String
        if let summaryData {
            let total = summaryData.totalTestCount ?? 0
            let failed = summaryData.failedTests ?? 0
            let skipped = summaryData.skippedTests ?? 0
            let executed = total - skipped
            // Zero executed tests must not pass silently: a task whose tests
            // did not run has not been verified.
            passed = result.exitCode == 0 && failed == 0 && executed > 0
            var text = "\(executed) executed, \(summaryData.passedTests ?? 0) passed, \(failed) failed, \(skipped) skipped"
            let failures = (summaryData.testFailures ?? []).compactMap { $0.testIdentifierString ?? $0.testName }
            if !failures.isEmpty {
                text += ". Failing: \(failures.joined(separator: ", "))"
            }
            if executed == 0 {
                text += ". No tests executed"
            }
            summaryText = text
        } else {
            // No parseable result bundle: fall back to the exit code but say so.
            passed = result.exitCode == 0
            summaryText = "xcodebuild test exit \(result.exitCode.map(String.init) ?? "signal") (no parseable .xcresult summary)"
        }

        return GradingResult(
            grader: identifier,
            passed: passed,
            duration: start.duration(to: .now),
            summary: summaryText,
            evidence: evidence
        )
    }

    /// True when the run died before any test could make an assertion —
    /// the app failed to install, or the runner never attached. These are the
    /// host having a bad moment, most often after a long series of UI runs.
    private static func isHostFailure(_ result: ProcessExecutionResult) -> Bool {
        guard result.exitCode != 0 else { return false }
        let output = result.standardOutput + result.standardError
        return output.contains("-Runner encountered an error")
            || output.contains("Failed to establish communication with the test runner")
            || output.contains("Test runner never began executing")
            || output.contains("Simulator device failed to install the application")
            || output.contains("Unable to boot the Simulator")
            || output.contains("Failed to load the test bundle")
    }

}
