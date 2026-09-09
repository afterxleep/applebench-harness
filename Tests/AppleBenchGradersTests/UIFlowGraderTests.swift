import AppleBenchCore
import Foundation
import Testing
@testable import AppleBenchGraders

@Suite("UI flow grader")
struct UIFlowGraderTests {
    @Test("Assertions use a settled screen read after UI steps")
    func stepsAreJudgedAfterTheUISettles() async throws {
        let graderRunner = FakeProcessRunner()
        graderRunner.enqueue(exitCode: 0, standardOutput: "** BUILD SUCCEEDED **\n")
        graderRunner.enqueue(exitCode: 0, standardOutput: screen(labels: ["Show settled"]))
        graderRunner.enqueue(exitCode: 0, standardOutput: batch(labels: ["Show settled"]))
        graderRunner.enqueue(exitCode: 0, standardOutput: screen(labels: ["Show settled", "Row 2"]))

        let simulatorRunner = FakeProcessRunner()
        simulatorRunner.enqueue(exitCode: 0) // install
        simulatorRunner.enqueue(exitCode: 0) // terminate before launch
        simulatorRunner.enqueue(exitCode: 0, standardOutput: "com.example.app: 100\n")
        simulatorRunner.enqueue(exitCode: 0) // terminate after grading

        let derivedData = FileManager.default.temporaryDirectory
            .appendingPathComponent("applebench-uiflow-derived-\(UUID().uuidString)")
        let app = derivedData.appendingPathComponent("Build/Products/Debug-iphonesimulator/App.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: derivedData) }

        let (context, workspace) = try await makeGradingContext(
            processRunner: graderRunner,
            derivedData: derivedData,
            simulatorUDID: "SIM-1"
        )
        defer { try? FileManager.default.removeItem(at: workspace) }

        let grader = UIFlowGrader(
            configuration: UIFlowGraderConfiguration(
                scheme: "App",
                bundleIdentifier: "com.example.app",
                steps: [.object(["action": .string("tap"), "target": .string("show-settled")])],
                assertions: [UIFlowAssertion(text: "Row 2")],
                settleSeconds: 0
            ),
            simulatorManager: SimulatorManager(processRunner: simulatorRunner)
        )

        let result = try await grader.grade(task: defaultTask(), context: context)

        #expect(result.passed)
        #expect(graderRunner.commands().filter { $0.arguments.prefix(3) == ["ui", "simulator", "screen"] }.count == 2)
    }

    @Test("Post-gesture steps run after the precise gesture and are judged after settling")
    func postGestureStepsRunAfterGestures() async throws {
        let graderRunner = FakeProcessRunner()
        graderRunner.enqueue(exitCode: 0, standardOutput: "** BUILD SUCCEEDED **\n")
        graderRunner.enqueue(exitCode: 0, standardOutput: screen(labels: ["Row 3"]))
        graderRunner.enqueue(exitCode: 0, standardOutput: screen(labels: ["Row 3"]))
        graderRunner.enqueue(exitCode: 0) // precise swipe
        graderRunner.enqueue(exitCode: 0, standardOutput: batch(labels: ["Row 2"]))
        graderRunner.enqueue(exitCode: 0, standardOutput: screen(labels: ["Row 2"]))

        let simulatorRunner = FakeProcessRunner()
        simulatorRunner.enqueue(exitCode: 0) // install
        simulatorRunner.enqueue(exitCode: 0) // terminate before launch
        simulatorRunner.enqueue(exitCode: 0, standardOutput: "com.example.app: 100\n")
        simulatorRunner.enqueue(exitCode: 0) // terminate after grading

        let derivedData = FileManager.default.temporaryDirectory
            .appendingPathComponent("applebench-uiflow-derived-\(UUID().uuidString)")
        let app = derivedData.appendingPathComponent("Build/Products/Debug-iphonesimulator/App.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: derivedData) }

        let (context, workspace) = try await makeGradingContext(
            processRunner: graderRunner,
            derivedData: derivedData,
            simulatorUDID: "SIM-1"
        )
        defer { try? FileManager.default.removeItem(at: workspace) }

        let grader = UIFlowGrader(
            configuration: UIFlowGraderConfiguration(
                scheme: "App",
                bundleIdentifier: "com.example.app",
                assertions: [UIFlowAssertion(text: "Row 2")],
                settleSeconds: 0,
                gestures: [UIFlowGesture(from: "380,309", to: "8,309")],
                postGestureSteps: [
                    .object(["action": .string("tap"), "target": .string("show-settled")])
                ]
            ),
            simulatorManager: SimulatorManager(processRunner: simulatorRunner)
        )

        let result = try await grader.grade(task: defaultTask(), context: context)

        let commands = graderRunner.commands()
        let swipeIndex = try #require(commands.firstIndex { $0.arguments.contains("swipe") })
        let batchIndex = try #require(commands.firstIndex { $0.arguments.contains("batch") })
        #expect(swipeIndex < batchIndex)
        #expect(result.passed)
    }

    @Test("A normal launch is retried when the first screen is SpringBoard")
    func normalLaunchRetriesUntilAppIsForeground() async throws {
        let graderRunner = FakeProcessRunner()
        graderRunner.enqueue(exitCode: 0, standardOutput: "** BUILD SUCCEEDED **\n")
        graderRunner.enqueue(exitCode: 0, standardOutput: screen(labels: ["Files", "Contacts"]))
        graderRunner.enqueue(exitCode: 0, standardOutput: screen(labels: ["Ready"]))
        graderRunner.enqueue(exitCode: 0, standardOutput: screen(labels: ["Ready"]))

        let simulatorRunner = FakeProcessRunner()
        simulatorRunner.enqueue(exitCode: 0) // install
        simulatorRunner.enqueue(exitCode: 0) // terminate before launch
        simulatorRunner.enqueue(exitCode: 0, standardOutput: "com.example.app: 100\n")
        simulatorRunner.enqueue(exitCode: 0, standardOutput: "com.example.app: 101\n")
        simulatorRunner.enqueue(exitCode: 0) // terminate after grading

        let derivedData = FileManager.default.temporaryDirectory
            .appendingPathComponent("applebench-uiflow-derived-\(UUID().uuidString)")
        let app = derivedData.appendingPathComponent("Build/Products/Debug-iphonesimulator/App.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: derivedData) }

        let (context, workspace) = try await makeGradingContext(
            processRunner: graderRunner,
            derivedData: derivedData,
            simulatorUDID: "SIM-1"
        )
        defer { try? FileManager.default.removeItem(at: workspace) }

        let grader = UIFlowGrader(
            configuration: UIFlowGraderConfiguration(
                scheme: "App",
                bundleIdentifier: "com.example.app",
                assertions: [UIFlowAssertion(text: "Ready")],
                settleSeconds: 0
            ),
            simulatorManager: SimulatorManager(processRunner: simulatorRunner)
        )
        let result = try await grader.grade(task: defaultTask(), context: context)

        let launches = simulatorRunner.commands().filter {
            $0.arguments.prefix(2) == ["simctl", "launch"]
        }
        #expect(launches.count == 2)
        #expect(result.passed)
    }

    @Test("Repeated UI graders keep distinct build evidence")
    func repeatedGradersKeepDistinctBuildLogs() async throws {
        let graderRunner = FakeProcessRunner()
        for _ in 0..<2 {
            graderRunner.enqueue(exitCode: 0, standardOutput: "** BUILD SUCCEEDED **\n")
            graderRunner.enqueue(exitCode: 0, standardOutput: screen(labels: ["Ready"]))
            graderRunner.enqueue(exitCode: 0, standardOutput: screen(labels: ["Ready"]))
        }

        let simulatorRunner = FakeProcessRunner()
        for pid in 100...101 {
            simulatorRunner.enqueue(exitCode: 0)
            simulatorRunner.enqueue(exitCode: 0)
            simulatorRunner.enqueue(exitCode: 0, standardOutput: "com.example.app: \(pid)\n")
            simulatorRunner.enqueue(exitCode: 0)
        }

        let derivedData = FileManager.default.temporaryDirectory
            .appendingPathComponent("applebench-uiflow-derived-\(UUID().uuidString)")
        let app = derivedData.appendingPathComponent("Build/Products/Debug-iphonesimulator/App.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: derivedData) }

        let (context, workspace) = try await makeGradingContext(
            processRunner: graderRunner,
            derivedData: derivedData,
            simulatorUDID: "SIM-1"
        )
        defer { try? FileManager.default.removeItem(at: workspace) }
        let grader = UIFlowGrader(
            configuration: UIFlowGraderConfiguration(
                scheme: "App",
                bundleIdentifier: "com.example.app",
                assertions: [UIFlowAssertion(text: "Ready")],
                settleSeconds: 0
            ),
            simulatorManager: SimulatorManager(processRunner: simulatorRunner)
        )

        let first = try await grader.grade(task: defaultTask(), context: context)
        let second = try await grader.grade(task: defaultTask(), context: context)

        #expect(first.evidence.contains { $0.name == "uiflow-build.log" })
        #expect(second.evidence.contains { $0.name == "uiflow-build-2.log" })
        #expect(FileManager.default.fileExists(atPath: workspace.appendingPathComponent("uiflow-build.log").path))
        #expect(FileManager.default.fileExists(atPath: workspace.appendingPathComponent("uiflow-build-2.log").path))
    }

    private func screen(labels: [String]) -> String {
        let tree = labels.enumerated().map { index, label in
            [
                "role": "StaticText",
                "label": label,
                "frame": ["x": 0, "y": index * 40, "width": 200, "height": 40],
            ] as [String: Any]
        }
        let document: [String: Any] = [
            "accessibility": ["orientation": "portrait", "tree": tree]
        ]
        let data = try! JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private func batch(labels: [String]) -> String {
        let screenData = Data(screen(labels: labels).utf8)
        let screen = try! JSONSerialization.jsonObject(with: screenData) as! [String: Any]
        let document: [String: Any] = ["final": screen, "steps": []]
        let data = try! JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}
