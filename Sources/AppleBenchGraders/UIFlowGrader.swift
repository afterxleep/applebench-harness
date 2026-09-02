import AppleBenchCore
import Foundation

/// Builds and installs the app, puts the device into the graded state, drives
/// the app through FlowDeck, and judges the accessibility tree it leaves.
///
/// Every other grader in the harness asks `xcodebuild` a question. This one
/// asks the device, which is the only way to grade behaviour that depends on
/// how the device itself is configured — rotation, system language, Dynamic
/// Type, an app that has been backgrounded with the Home button. Two of those
/// have no `simctl` equivalent, so this grader is also the reason a task can
/// require them at all.
public struct UIFlowGrader: Grader {
    public let identifier = "uiflow"
    private let configuration: UIFlowGraderConfiguration
    private let simulatorManager: SimulatorManager

    public init(
        configuration: UIFlowGraderConfiguration,
        simulatorManager: SimulatorManager = SimulatorManager()
    ) {
        self.configuration = configuration
        self.simulatorManager = simulatorManager
    }

    public func grade(task: BenchmarkTask, context: GradingContext) async throws -> GradingResult {
        let start = ContinuousClock.now
        try configuration.validate()

        guard let udid = context.simulatorUDID else {
            throw BenchmarkFailure.graderFailure(
                grader: identifier,
                message: "A UI flow needs a simulator; the task declares none"
            )
        }

        var buildArguments = XcodebuildSupport.baseArguments(
            project: configuration.project,
            workspace: configuration.workspace,
            scheme: configuration.scheme,
            configuration: nil,
            destination: nil,
            context: context
        )
        buildArguments.append("build")
        let (buildResult, buildLog) = try await XcodebuildSupport.run(
            arguments: buildArguments,
            logName: "uiflow-build.log",
            context: context
        )
        guard buildResult.exitCode == 0 else {
            return GradingResult(
                grader: identifier,
                passed: false,
                duration: start.duration(to: .now),
                summary: "App failed to build, so the flow could not run",
                evidence: [buildLog]
            )
        }
        guard let appURL = RuntimeGrader.findAppBundle(in: context.derivedDataURL) else {
            throw BenchmarkFailure.graderFailure(
                grader: identifier,
                message: "Built products contain no .app bundle under \(context.derivedDataURL.path)"
            )
        }

        let state = configuration.deviceState ?? SimulatorDeviceState()
        let applier = SimulatorDeviceStateApplier(grader: identifier, context: context)

        var evidence = [buildLog]
        let outcome: Outcome = try await applier.withState(state) {
            // Installed after the language/appearance settings are in place:
            // setting the system language reboots the device, which would drop
            // an install done first.
            try await simulatorManager.install(udid: udid, appURL: appURL)
            _ = try? await simulatorManager.terminate(
                udid: udid,
                bundleIdentifier: configuration.bundleIdentifier
            )
            _ = try await simulatorManager.launch(
                udid: udid,
                bundleIdentifier: configuration.bundleIdentifier
            )
            try? await Task.sleep(for: .seconds(configuration.settleSeconds))

            var stepFailure: String?
            var snapshot: UIFlowSnapshot

            if configuration.steps.isEmpty {
                snapshot = try await readScreen(udid: udid, context: context)
            } else {
                let response = try await runBatch(udid: udid, context: context)
                stepFailure = response.stepFailure
                snapshot = response.snapshot
            }

            guard stepFailure == nil else {
                return Outcome(stepFailure: stepFailure, snapshot: snapshot)
            }

            // The second state turns the device under a running app. Nested so
            // it is reset before the first state is, leaving the simulator the
            // way the flow found it.
            let after = configuration.afterState ?? SimulatorDeviceState()
            return try await applier.withState(after) {
                if !after.isEmpty {
                    try? await Task.sleep(for: .seconds(configuration.settleSeconds))
                    snapshot = try await readScreen(udid: udid, context: context)
                }
                for button in configuration.buttons {
                    let command = ProcessCommand(
                        executable: "flowdeck",
                        arguments: ["simulator", "button", button, "-S", udid]
                    )
                    let result = try await context.runRecorded(command, timeout: .seconds(60))
                    guard result.exitCode == 0 else {
                        throw BenchmarkFailure.graderFailure(
                            grader: identifier,
                            message: "Could not press \(button): \(result.standardError.trimmed())"
                        )
                    }
                }
                if !configuration.buttons.isEmpty {
                    try? await Task.sleep(for: .seconds(configuration.settleSeconds))
                    snapshot = try await readScreen(udid: udid, context: context)
                }
                return Outcome(stepFailure: nil, snapshot: snapshot)
            }
        }

        if let treeArtifact = write(outcome.snapshot, in: context) {
            evidence.append(treeArtifact)
            await context.recorder.record(
                .artifactCreated,
                payload: .object(["path": .string(treeArtifact.path)])
            )
        }
        await simulatorManager.terminate(udid: udid, bundleIdentifier: configuration.bundleIdentifier)

        var described = state.summary
        if let after = configuration.afterState, !after.isEmpty {
            described += described == "default" ? "then \(after.summary)" : ", then \(after.summary)"
        }
        let context = "in \(described)"
        if let stepFailure = outcome.stepFailure {
            return GradingResult(
                grader: identifier,
                passed: false,
                duration: start.duration(to: .now),
                summary: "The flow could not be driven \(context): \(stepFailure)",
                evidence: evidence
            )
        }

        let failures = configuration.assertions.compactMap { $0.failure(against: outcome.snapshot) }
        return GradingResult(
            grader: identifier,
            passed: failures.isEmpty,
            duration: start.duration(to: .now),
            summary: failures.isEmpty
                ? "\(configuration.assertions.count) UI assertion(s) hold \(context)"
                : "\(failures.count) of \(configuration.assertions.count) UI assertion(s) failed "
                    + "\(context): " + failures.joined(separator: "; "),
            evidence: evidence
        )
    }

    private struct Outcome {
        var stepFailure: String?
        var snapshot: UIFlowSnapshot
    }

    private func runBatch(udid: String, context: GradingContext) async throws -> UIFlowBatchResponse {
        let steps = try JSONEncoder().encode(configuration.steps)
        let command = ProcessCommand(
            executable: "flowdeck",
            arguments: [
                "ui", "simulator", "batch",
                "--steps", String(decoding: steps, as: UTF8.self),
                "-S", udid, "--json",
            ]
        )
        let result = try await context.runRecorded(command, timeout: .seconds(300))
        // A non-zero exit means a step did not complete, which is a grading
        // outcome, not a broken grader — the response still carries the tree.
        return try UIFlowBatchResponse(json: Data(result.standardOutput.utf8))
    }

    private func readScreen(udid: String, context: GradingContext) async throws -> UIFlowSnapshot {
        let command = ProcessCommand(
            executable: "flowdeck",
            arguments: ["ui", "simulator", "screen", "-S", udid, "--json"]
        )
        let result = try await context.runRecorded(command, timeout: .seconds(180))
        guard result.exitCode == 0 else {
            throw BenchmarkFailure.graderFailure(
                grader: identifier,
                message: "Could not read the screen: \(result.standardError.trimmed())"
            )
        }
        // `screen` returns the snapshot document directly; the batch parser
        // expects it nested under `final`, so wrap it rather than writing a
        // second parser for the same payload.
        guard let document = try? JSONSerialization.jsonObject(with: Data(result.standardOutput.utf8)) else {
            throw BenchmarkFailure.graderFailure(
                grader: identifier,
                message: "The screen read returned output that is not JSON"
            )
        }
        let wrapped = try JSONSerialization.data(withJSONObject: ["final": document, "steps": []])
        return try UIFlowBatchResponse(json: wrapped).snapshot
    }

    /// The tree the grade was made from, so a disputed result can be re-read.
    private func write(_ snapshot: UIFlowSnapshot, in context: GradingContext) -> Artifact? {
        let rows = snapshot.elements.map { element in
            [
                "role": element.role,
                "id": element.id ?? "",
                "label": element.label ?? "",
                "value": element.value ?? "",
                "frame": "\(element.frame.x),\(element.frame.y),\(element.frame.width),\(element.frame.height)",
            ]
        }
        let document: [String: Any] = ["orientation": snapshot.orientation, "elements": rows]
        guard let data = try? JSONSerialization.data(
            withJSONObject: document,
            options: [.prettyPrinted, .sortedKeys]
        ) else { return nil }
        // A task normally carries several uiflow graders — the default state
        // and the state under test — and a fixed filename would leave only the
        // last one's tree behind, which is the one nobody needs to inspect.
        var name = "uiflow-tree.json"
        var suffix = 2
        while FileManager.default.fileExists(
            atPath: context.artifactsDirectoryURL.appendingPathComponent(name).path
        ) {
            name = "uiflow-tree-\(suffix).json"
            suffix += 1
        }
        let url = context.artifactsDirectoryURL.appendingPathComponent(name)
        guard (try? data.write(to: url)) != nil else { return nil }
        return Artifact(name: name, path: "logs/\(name)")
    }
}
