import AppleBenchCore
import Foundation

/// Verifies the workspace builds by running a fresh, independent
/// `xcodebuild build` with clean derived data. Whatever the agent built (or
/// claimed to build) during its run does not count.
public struct BuildGrader: Grader {
    public let identifier = "build"
    private let configuration: BuildGraderConfiguration

    public init(configuration: BuildGraderConfiguration) {
        self.configuration = configuration
    }

    public func grade(task: BenchmarkTask, context: GradingContext) async throws -> GradingResult {
        let start = ContinuousClock.now

        var arguments = XcodebuildSupport.baseArguments(
            project: configuration.project,
            workspace: configuration.workspace,
            scheme: configuration.scheme,
            configuration: configuration.configuration,
            destination: configuration.destination,
            context: context
        )
        let resultBundle = XcodebuildSupport.resultBundleURL(named: "build", context: context)
        arguments += ["-resultBundlePath", resultBundle.path, "build"]

        // A Swift package has no project file to point at: xcodebuild finds
        // `Package.swift` in its working directory instead.
        let (result, logArtifact) = try await XcodebuildSupport.run(
            arguments: arguments,
            logName: "build.log",
            context: context,
            workingDirectory: XcodebuildSupport.packageDirectory(named: configuration.project, context: context)
        )

        var evidence = [logArtifact]
        if FileManager.default.fileExists(atPath: resultBundle.path) {
            evidence.append(Artifact(name: resultBundle.lastPathComponent, path: "logs/\(resultBundle.lastPathComponent)"))
        }

        let passed = result.exitCode == 0
        let summary = passed
            ? "xcodebuild build succeeded for scheme '\(configuration.scheme)'"
            : "xcodebuild build failed (exit \(result.exitCode.map(String.init) ?? "signal")) for scheme '\(configuration.scheme)'"

        return GradingResult(
            grader: identifier,
            passed: passed,
            duration: start.duration(to: .now),
            summary: summary,
            evidence: evidence
        )
    }
}
