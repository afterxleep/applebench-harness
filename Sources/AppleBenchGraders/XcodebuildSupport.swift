import AppleBenchCore
import Foundation

/// Shared helpers for graders that drive `xcodebuild`.
enum XcodebuildSupport {
    /// Generous ceiling for a single xcodebuild invocation; a grader hitting
    /// this is an infrastructure problem, not a benchmark FAIL.
    static let invocationTimeout: Duration = .seconds(1800)

    /// Builds the common xcodebuild argument list from grader configuration.
    static func baseArguments(
        project: String?,
        workspace: String?,
        scheme: String,
        configuration: String?,
        destination: String?,
        context: GradingContext
    ) -> [String] {
        var arguments: [String] = []
        if let workspace {
            arguments += ["-workspace", workspace]
        } else if let project {
            // A Swift package has no `.xcodeproj` to point at, and `-project`
            // on its directory fails to open. xcodebuild finds `Package.swift`
            // in its working directory instead, so a package contributes no
            // project flag at all.
            if packageDirectory(named: project, context: context) == nil {
                arguments += ["-project", project]
            }
        }
        arguments += ["-scheme", scheme]
        if let configuration {
            arguments += ["-configuration", configuration]
        }
        if let destination = destination ?? context.destination {
            arguments += ["-destination", destination]
        }
        // Fresh derived data per run so the agent's build state cannot leak
        // into grading.
        arguments += ["-derivedDataPath", context.derivedDataURL.path]
        return arguments
    }

    /// The workspace-relative directory `project` names, when it holds a
    /// `Package.swift` rather than an `.xcodeproj`.
    static func packageDirectory(named project: String?, context: GradingContext) -> URL? {
        guard let project, !project.hasSuffix(".xcodeproj"), !project.hasSuffix(".xcworkspace") else {
            return nil
        }
        let directory = context.workspaceURL.appendingPathComponent(project, isDirectory: true)
        let manifest = directory.appendingPathComponent("Package.swift")
        return FileManager.default.fileExists(atPath: manifest.path) ? directory : nil
    }

    /// Uninstalls every app the grading build produced and resets its privacy
    /// grants on the run's simulator.
    ///
    /// Graders run one after another against the same simulator. Without this,
    /// a count persisted by one test run, or a permission granted to it, is
    /// already there when the next run starts, and a test that passed a
    /// moment ago fails its baseline for a reason the agent never caused.
    static func resetAppState(context: GradingContext) async {
        guard let udid = context.simulatorUDID else { return }
        for bundleID in builtAppBundleIdentifiers(in: context.derivedDataURL) {
            for arguments in [
                ["simctl", "privacy", udid, "reset", "all", bundleID],
                ["simctl", "uninstall", udid, bundleID],
            ] {
                let command = ProcessCommand(
                    executable: "/usr/bin/xcrun",
                    arguments: arguments,
                    workingDirectory: context.workspaceURL
                )
                // Nothing installed yet, or nothing granted, is the clean
                // state this is asking for, so a failure is not an error.
                _ = try? await context.runRecorded(command, timeout: .seconds(60))
            }
        }
    }

    /// Bundle identifiers of the simulator apps under `derivedData`, leaving
    /// out the test runners XCTest builds alongside them.
    static func builtAppBundleIdentifiers(in derivedData: URL) -> [String] {
        let products = derivedData.appendingPathComponent("Build/Products", isDirectory: true)
        let fileManager = FileManager.default
        guard let configurations = try? fileManager.contentsOfDirectory(atPath: products.path) else { return [] }
        var identifiers: [String] = []
        for configuration in configurations.sorted() where configuration.hasSuffix("-iphonesimulator") {
            let directory = products.appendingPathComponent(configuration, isDirectory: true)
            let apps = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
            for app in apps.sorted() where app.hasSuffix(".app") && !app.hasSuffix("-Runner.app") {
                let plist = directory.appendingPathComponent(app).appendingPathComponent("Info.plist")
                guard let data = try? Data(contentsOf: plist),
                      let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                      let identifier = values["CFBundleIdentifier"] as? String,
                      !identifiers.contains(identifier)
                else { continue }
                identifiers.append(identifier)
            }
        }
        return identifiers
    }

    /// The first compiler error in xcodebuild output, when the run failed
    /// because something did not compile.
    static func firstCompileError(in result: ProcessExecutionResult) -> String? {
        let output = result.standardOutput + "\n" + result.standardError
        // A compiler diagnostic names a file, line and column. `xcodebuild:
        // error:` lines are about the invocation, such as a missing
        // destination, and reporting them as compile failures sent debugging
        // after source that was fine.
        guard let diagnostic = try? NSRegularExpression(pattern: #"^(\S[^:\n]*):\d+:\d+: error: (.+)$"#, options: [.anchorsMatchLines]) else {
            return nil
        }
        let range = NSRange(output.startIndex..., in: output)
        guard let match = diagnostic.firstMatch(in: output, range: range),
              let fileRange = Range(match.range(at: 1), in: output),
              let messageRange = Range(match.range(at: 2), in: output)
        else { return nil }
        let file = URL(fileURLWithPath: String(output[fileRange])).lastPathComponent
        return "\(file): \(output[messageRange])"
    }

    /// Whether a simulator with `udid` is still registered on the machine.
    /// When the listing cannot be read, the device is assumed present, so an
    /// unreadable listing never turns an agent failure into an excused one.
    static func simulatorExists(udid: String, context: GradingContext) async -> Bool {
        let command = ProcessCommand(
            executable: "/usr/bin/xcrun",
            arguments: ["simctl", "list", "devices", "--json"],
            workingDirectory: context.workspaceURL
        )
        guard let result = try? await context.runRecorded(command, timeout: .seconds(60)),
              result.exitCode == 0,
              let devices = try? SimulatorManager.allDeviceUDIDs(listJSON: result.standardOutput)
        else { return true }
        return devices.contains(udid)
    }

    /// Runs xcodebuild, saving full output as a log artifact.
    static func run(
        arguments: [String],
        logName: String,
        context: GradingContext,
        workingDirectory: URL? = nil
    ) async throws -> (result: ProcessExecutionResult, logArtifact: Artifact) {
        let command = ProcessCommand(
            executable: "/usr/bin/xcodebuild",
            arguments: arguments,
            workingDirectory: workingDirectory ?? context.workspaceURL
        )
        let result: ProcessExecutionResult
        do {
            result = try await context.runRecorded(command, timeout: invocationTimeout)
        } catch let error as ProcessRunnerError {
            // xcodebuild not launchable at all: infrastructure, not a FAIL.
            throw BenchmarkFailure.infrastructureFailure("\(error)")
        }
        if result.timedOut {
            throw BenchmarkFailure.infrastructureFailure(
                "xcodebuild exceeded the \(Int(invocationTimeout.seconds))s grader ceiling"
            )
        }

        if result.exitCode != 0,
           (result.standardOutput + result.standardError).contains("Unable to find a device matching the provided destination"),
           let udid = context.simulatorUDID,
           await !simulatorExists(udid: udid, context: context) {
            // The run's own simulator was deleted underneath it. Nothing the
            // agent did can cause that, and scoring it as a failed build or
            // test run charged a model for another process's cleanup.
            throw BenchmarkFailure.infrastructureFailure(
                "the run's simulator \(udid) no longer exists, so xcodebuild could not reach it"
            )
        }

        let logURL = context.artifactsDirectoryURL.appendingPathComponent(logName)
        let log = result.standardOutput + (result.standardError.isEmpty ? "" : "\n--- stderr ---\n" + result.standardError)
        try? log.write(to: logURL, atomically: true, encoding: .utf8)
        let artifact = Artifact(name: logName, path: "logs/\(logName)")
        await context.recorder.record(.artifactCreated, payload: .object(["path": .string(artifact.path)]))
        return (result, artifact)
    }

    /// One target's fully resolved build settings, as reported by
    /// `xcodebuild -showBuildSettings -json`.
    struct TargetBuildSettings: Decodable {
        var action: String?
        var target: String?
        var buildSettings: [String: String]
    }

    /// Fetches resolved build settings for a scheme as structured JSON.
    ///
    /// This is the only honest way to answer "what does this project actually
    /// configure": it reflects the resolved value after xcconfigs, inheritance,
    /// and target overrides, which reading `project.pbxproj` cannot.
    /// A non-zero exit or unparseable payload is an infrastructure failure,
    /// never a benchmark FAIL.
    static func showBuildSettings(
        project: String?,
        workspace: String?,
        scheme: String,
        configuration: String?,
        destination: String?,
        logName: String,
        context: GradingContext
    ) async throws -> [TargetBuildSettings] {
        var arguments = baseArguments(
            project: project,
            workspace: workspace,
            scheme: scheme,
            configuration: configuration,
            destination: destination,
            context: context
        )
        arguments += ["-showBuildSettings", "-json"]

        let (result, _) = try await run(arguments: arguments, logName: logName, context: context)
        guard result.exitCode == 0 else {
            throw BenchmarkFailure.infrastructureFailure(
                "xcodebuild -showBuildSettings failed (exit \(result.exitCode.map(String.init) ?? "signal")) "
                + "for scheme '\(scheme)': "
                + result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        // xcodebuild may prepend warnings before the JSON payload; take the
        // document from its first bracket rather than scraping line by line.
        guard let start = result.standardOutput.firstIndex(of: "["),
              let data = String(result.standardOutput[start...]).data(using: .utf8),
              let settings = try? JSONDecoder().decode([TargetBuildSettings].self, from: data)
        else {
            throw BenchmarkFailure.infrastructureFailure(
                "Could not parse xcodebuild -showBuildSettings -json output for scheme '\(scheme)'"
            )
        }
        return settings
    }

    /// Structured totals extracted from an `.xcresult` bundle via
    /// `xcresulttool get test-results summary` (preferred over regex-scraping
    /// terminal output).
    struct TestSummary: Decodable {
        struct Failure: Decodable {
            var testName: String?
            /// e.g. "CounterPersistenceTests/testCountSurvivesStoreRecreation()"
            /// (`testIdentifier` itself is numeric in Xcode 16+ summaries)
            var testIdentifierString: String?
            var failureText: String?
        }

        var totalTestCount: Int?
        var passedTests: Int?
        var failedTests: Int?
        var skippedTests: Int?
        var result: String?
        var testFailures: [Failure]?
    }

    static func testSummary(
        xcresultURL: URL,
        context: GradingContext
    ) async -> TestSummary? {
        // No file-existence pre-check: `xcresulttool` reports cleanly when
        // the bundle is absent, and skipping the check here keeps tests
        // honest (the faked xcodebuild does not write the bundle, so a
        // pre-check would always make the summary path unreachable).
        let command = ProcessCommand(
            executable: "/usr/bin/xcrun",
            arguments: ["xcresulttool", "get", "test-results", "summary", "--path", xcresultURL.path],
            workingDirectory: context.workspaceURL
        )
        guard let result = try? await context.runRecorded(command, timeout: .seconds(120)),
              result.exitCode == 0,
              let data = result.standardOutput.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode(TestSummary.self, from: data)
    }

    /// A unique (non-existing) result bundle path inside the artifacts dir.
    static func resultBundleURL(named name: String, context: GradingContext) -> URL {
        var candidate = context.artifactsDirectoryURL.appendingPathComponent("\(name).xcresult")
        var counter = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            counter += 1
            candidate = context.artifactsDirectoryURL.appendingPathComponent("\(name)-\(counter).xcresult")
        }
        return candidate
    }

    /// A non-existing artifact filename preserving the preferred extension.
    static func uniqueLogName(_ preferred: String, context: GradingContext) -> String {
        let preferredURL = URL(fileURLWithPath: preferred)
        let stem = preferredURL.deletingPathExtension().lastPathComponent
        let ext = preferredURL.pathExtension
        var candidate = preferred
        var counter = 2
        while FileManager.default.fileExists(
            atPath: context.artifactsDirectoryURL.appendingPathComponent(candidate).path
        ) {
            candidate = ext.isEmpty ? "\(stem)-\(counter)" : "\(stem)-\(counter).\(ext)"
            counter += 1
        }
        return candidate
    }
}
