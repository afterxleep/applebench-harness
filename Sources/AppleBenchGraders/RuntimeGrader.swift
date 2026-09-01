import AppleBenchCore
import Foundation

/// Builds, installs, and launches the app on the benchmark simulator, then
/// observes whether the process survives the configured window. v1 detects
/// launch failures and early crashes; it does not attempt visual
/// intelligence.
public struct RuntimeGrader: Grader {
    public let identifier = "runtime"
    private let configuration: RuntimeGraderConfiguration
    private let simulatorManager: SimulatorManager

    public init(configuration: RuntimeGraderConfiguration, simulatorManager: SimulatorManager = SimulatorManager()) {
        self.configuration = configuration
        self.simulatorManager = simulatorManager
    }

    public func grade(task: BenchmarkTask, context: GradingContext) async throws -> GradingResult {
        let start = ContinuousClock.now

        guard let udid = context.simulatorUDID else {
            throw BenchmarkFailure.infrastructureFailure(
                "Runtime grader requires a provisioned simulator; task must declare a simulator requirement"
            )
        }
        guard let scheme = configuration.scheme else {
            throw BenchmarkFailure.invalidTask("Runtime grader requires a 'scheme'")
        }

        // 1. Fresh build of the app.
        var buildArguments = XcodebuildSupport.baseArguments(
            project: configuration.project,
            workspace: configuration.workspace,
            scheme: scheme,
            configuration: nil,
            destination: nil,
            context: context
        )
        buildArguments.append("build")
        let (buildResult, logArtifact) = try await XcodebuildSupport.run(
            arguments: buildArguments,
            logName: "runtime-build.log",
            context: context
        )
        guard buildResult.exitCode == 0 else {
            return GradingResult(
                grader: identifier,
                passed: false,
                duration: start.duration(to: .now),
                summary: "App failed to build for runtime verification",
                evidence: [logArtifact]
            )
        }

        // 2. Locate the built .app in this run's derived data.
        guard let appURL = Self.findAppBundle(in: context.derivedDataURL) else {
            throw BenchmarkFailure.infrastructureFailure(
                "Built products contain no .app bundle under \(context.derivedDataURL.path)"
            )
        }

        // 3. Install and launch on the benchmark simulator.
        try await simulatorManager.install(udid: udid, appURL: appURL)
        let pid: pid_t
        do {
            pid = try await simulatorManager.launch(udid: udid, bundleIdentifier: configuration.launch.bundleIdentifier)
        } catch {
            return GradingResult(
                grader: identifier,
                passed: false,
                duration: start.duration(to: .now),
                summary: "App failed to launch: \(error)",
                evidence: [logArtifact]
            )
        }

        // 4. Observe survival for the configured window.
        try? await Task.sleep(for: .seconds(configuration.observationSeconds))
        let alive = simulatorManager.isProcessAlive(pid)

        // 5. Evidence: screenshot of the final state, best effort.
        var evidence = [logArtifact]
        let screenshotURL = context.artifactsDirectoryURL.appendingPathComponent("runtime-final.png")
        if (try? await simulatorManager.screenshot(udid: udid, to: screenshotURL)) != nil {
            let artifact = Artifact(name: "runtime-final.png", path: "logs/runtime-final.png")
            evidence.append(artifact)
            await context.recorder.record(.artifactCreated, payload: .object(["path": .string(artifact.path)]))
        }

        await simulatorManager.terminate(udid: udid, bundleIdentifier: configuration.launch.bundleIdentifier)

        let passed = configuration.mustNotCrash ? alive : true
        return GradingResult(
            grader: identifier,
            passed: passed,
            duration: start.duration(to: .now),
            summary: alive
                ? "Process survived \(configuration.observationSeconds)s observation window"
                : "Process terminated within \(configuration.observationSeconds)s of launch",
            evidence: evidence
        )
    }

    /// Finds the first `.app` bundle in the simulator build products.
    static func findAppBundle(in derivedDataURL: URL) -> URL? {
        let productsURL = derivedDataURL.appendingPathComponent("Build/Products")
        guard let configurations = try? FileManager.default.contentsOfDirectory(
            at: productsURL,
            includingPropertiesForKeys: nil
        ) else { return nil }
        for configuration in configurations where configuration.lastPathComponent.contains("iphonesimulator") {
            if let contents = try? FileManager.default.contentsOfDirectory(at: configuration, includingPropertiesForKeys: nil),
               let app = contents.first(where: { $0.pathExtension == "app" }) {
                return app
            }
        }
        return nil
    }
}
