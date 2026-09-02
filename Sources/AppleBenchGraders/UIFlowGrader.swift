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
            // Both need the app on the device: one wipes its container, the
            // other names it in a permission database.
            if configuration.clearState {
                try await require(
                    UIFlowCommands.clearState(
                        bundleIdentifier: configuration.bundleIdentifier, udid: udid
                    ),
                    context: context
                )
            }
            for change in configuration.privacy {
                try await require(
                    UIFlowCommands.privacy(
                        change, bundleIdentifier: configuration.bundleIdentifier, udid: udid
                    ),
                    context: context
                )
            }
            _ = try await simulatorManager.launch(
                udid: udid,
                bundleIdentifier: configuration.bundleIdentifier
            )
            try? await Task.sleep(for: .seconds(configuration.settleSeconds))

            // A state change that reboots the device leaves SpringBoard racing
            // the launch: `simctl launch` reports a pid, SpringBoard finishes
            // coming up, and the app is behind the home screen. Grading that
            // reads the home screen's icons as the app's UI and reports a
            // sound task as passing unfixed. Confirm the app is actually in
            // front, and relaunch once if it is not.
            if state.reboots {
                for attempt in 0..<3 {
                    let screen = try await readScreen(udid: udid, context: context)
                    if !Self.looksLikeHomeScreen(screen) { break }
                    guard attempt < 2 else {
                        throw BenchmarkFailure.graderFailure(
                            grader: identifier,
                            message: "The app never came to the front after the device restarted; "
                                + "the home screen was still showing after three launches."
                        )
                    }
                    _ = try? await simulatorManager.launch(
                        udid: udid,
                        bundleIdentifier: configuration.bundleIdentifier
                    )
                    try? await Task.sleep(for: .seconds(configuration.settleSeconds + 3))
                }
            }

            if let openURL = configuration.openURL {
                try await require(UIFlowCommands.openURL(openURL, udid: udid), context: context)
                try? await Task.sleep(for: .seconds(configuration.settleSeconds))
            }

            var stepFailure: String?
            var snapshot: UIFlowSnapshot

            if configuration.steps.isEmpty {
                snapshot = try await readScreen(udid: udid, context: context)
            } else {
                let response = try await runBatch(configuration.steps, udid: udid, context: context)
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
                if !configuration.afterSteps.isEmpty {
                    let response = try await runBatch(
                        configuration.afterSteps, udid: udid, context: context
                    )
                    if let failure = response.stepFailure {
                        return Outcome(stepFailure: failure, snapshot: response.snapshot)
                    }
                    snapshot = response.snapshot
                }
                for gesture in configuration.gestures {
                    try await require(UIFlowCommands.swipe(gesture, udid: udid), context: context)
                    try? await Task.sleep(for: .seconds(1))
                }
                for button in configuration.buttons {
                    try await require(UIFlowCommands.button(button, udid: udid), context: context)
                }
                if let push = configuration.push {
                    let payload = context.workspaceURL.appendingPathComponent(push).path
                    try await require(
                        UIFlowCommands.push(
                            payload: payload,
                            bundleIdentifier: configuration.bundleIdentifier,
                            udid: udid
                        ),
                        context: context
                    )
                    try? await Task.sleep(for: .seconds(configuration.settleSeconds))
                }
                if configuration.memoryWarning {
                    try await require(UIFlowCommands.memoryWarning(udid: udid), context: context)
                    try? await Task.sleep(for: .seconds(configuration.settleSeconds))
                }
                if configuration.reinstall {
                    await simulatorManager.terminate(
                        udid: udid,
                        bundleIdentifier: configuration.bundleIdentifier
                    )
                    try await simulatorManager.install(udid: udid, appURL: appURL)
                    _ = try await simulatorManager.launch(
                        udid: udid,
                        bundleIdentifier: configuration.bundleIdentifier
                    )
                }
                if configuration.relaunch {
                    await simulatorManager.terminate(
                        udid: udid,
                        bundleIdentifier: configuration.bundleIdentifier
                    )
                    try? await Task.sleep(for: .seconds(1))
                    _ = try await simulatorManager.launch(
                        udid: udid,
                        bundleIdentifier: configuration.bundleIdentifier
                    )
                }
                if !configuration.buttons.isEmpty || !configuration.gestures.isEmpty
                    || configuration.relaunch
                    || configuration.reinstall || configuration.push != nil
                    || configuration.memoryWarning {
                    try? await Task.sleep(for: .seconds(configuration.settleSeconds))
                    snapshot = try await readScreen(udid: udid, context: context)
                }
                var appearance: String?
                if configuration.appearanceMustDiffer {
                    appearance = try await appearanceFailure(
                        udid: udid, context: context, snapshot: snapshot
                    )
                }
                return Outcome(
                    stepFailure: nil, snapshot: snapshot, appearanceFailure: appearance
                )
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

        var failures = configuration.assertions.compactMap { $0.failure(against: outcome.snapshot) }
        if let appearance = outcome.appearanceFailure { failures.append(appearance) }
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

    /// SpringBoard, rather than the app under test. Identified by the icons it
    /// always carries — an app's own screen does not show Files next to Watch.
    static func looksLikeHomeScreen(_ snapshot: UIFlowSnapshot) -> Bool {
        let labels = Set(snapshot.elements.compactMap(\.label))
        return labels.contains("Files") && labels.contains("Contacts")
    }

    /// Runs a command the flow depends on. A device instruction that did not
    /// take is a broken grader, not a failing app: the task asked to be judged
    /// with the permission revoked, and judging it granted answers a different
    /// question.
    private func require(_ command: ProcessCommand, context: GradingContext) async throws {
        let result = try await context.runRecorded(command, timeout: .seconds(120))
        guard result.exitCode == 0 else {
            throw BenchmarkFailure.graderFailure(
                grader: identifier,
                message: "\(command.displayString) failed: \(result.standardError.trimmed())"
            )
        }
    }

    private struct Outcome {
        var stepFailure: String?
        var snapshot: UIFlowSnapshot
        var appearanceFailure: String?
    }

    /// Captures the screen in light and again in dark, and reports when the two
    /// are the same picture.
    private func appearanceFailure(
        udid: String,
        context: GradingContext,
        snapshot: UIFlowSnapshot
    ) async throws -> String? {
        let applier = SimulatorDeviceStateApplier(grader: identifier, context: context)
        let light = context.artifactsDirectoryURL.appendingPathComponent("appearance-light.png")
        let dark = context.artifactsDirectoryURL.appendingPathComponent("appearance-dark.png")

        try await applier.withState(SimulatorDeviceState(appearance: "light")) {
            try? await Task.sleep(for: .seconds(configuration.settleSeconds))
            try await capture(to: light, udid: udid, context: context)
        }
        try await applier.withState(SimulatorDeviceState(appearance: "dark")) {
            try? await Task.sleep(for: .seconds(configuration.settleSeconds))
            try await capture(to: dark, udid: udid, context: context)
        }

        // Limited to the element under test when the task names one.
        var crop: CGRect?
        var screen: CGSize?
        if let region = configuration.appearanceRegion {
            guard let element = snapshot.element(id: region, label: region) else {
                return "no element \"\(region)\" on screen to compare appearances of"
            }
            crop = CGRect(
                x: CGFloat(element.frame.x), y: CGFloat(element.frame.y),
                width: CGFloat(element.frame.width), height: CGFloat(element.frame.height)
            )
            if let root = snapshot.root {
                screen = CGSize(width: CGFloat(root.width), height: CGFloat(root.height))
            }
        }
        let difference = try ScreenshotComparison.difference(
            light, dark, crop: crop, screenSize: screen
        )
        // A screen that adapts turns over most of its area. The floor is set
        // well below that and well above the few percent a status bar clock or
        // a caret can move on its own.
        guard difference < 0.08 else { return nil }
        return String(
            format: "%@ renders the same in light and dark (%.1f%% different); "
                + "its colours do not follow the appearance",
            configuration.appearanceRegion.map { "\"\($0)\"" } ?? "the screen",
            difference * 100
        )
    }

    private func capture(to url: URL, udid: String, context: GradingContext) async throws {
        try await require(
            ProcessCommand(
                executable: "flowdeck",
                arguments: ["ui", "simulator", "screen", "-o", url.path, "-S", udid, "--json"]
            ),
            context: context
        )
    }

    private func runBatch(
        _ steps: [JSONValue],
        udid: String,
        context: GradingContext
    ) async throws -> UIFlowBatchResponse {
        let steps = try JSONEncoder().encode(steps)
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
