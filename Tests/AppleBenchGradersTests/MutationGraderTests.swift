import AppleBenchCore
import Foundation
import Testing
@testable import AppleBenchGraders

@Suite("Mutation grader")
struct MutationGraderTests {
    @Test("Mutation runs do not wait on simulator diagnostics")
    func skipsTestDiagnosticsCollection() async throws {
        let runner = FakeProcessRunner()
        runner.setUniversal(exitCode: 0)
        let (context, workspace) = try await makeGradingContext(processRunner: runner)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let sourceURL = workspace.appendingPathComponent("Sources/View.swift")
        try FileManager.default.createDirectory(
            at: sourceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try #"Text("Summary")"#.write(to: sourceURL, atomically: true, encoding: .utf8)

        _ = try await MutationGrader(configuration: MutationGraderConfiguration(
            project: "App.xcodeproj",
            scheme: "App",
            mutations: [
                SourceMutation(path: "Sources/View.swift", replace: "Summary", with: "Mutated"),
            ]
        )).grade(task: defaultTask(), context: context)

        // A mutated run is expected to fail, and xcodebuild spends up to ten
        // minutes collecting diagnostics from the simulator after a failure
        // unless it is told not to.
        let builds = runner.commands().filter { $0.executable == "/usr/bin/xcodebuild" }
        #expect(!builds.isEmpty)
        for build in builds {
            #expect(build.arguments.contains("-collect-test-diagnostics"))
            #expect(build.arguments.contains("never"))
        }
    }

    @Test("An already failing unmutated test cannot pass mutation grading")
    func rejectsBrokenBaseline() async throws {
        let runner = FakeProcessRunner()
        runner.enqueue(exitCode: 65, standardError: "UI test target does not compile")
        let (context, workspace) = try await makeGradingContext(processRunner: runner)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let sourceURL = workspace.appendingPathComponent("Sources/View.swift")
        try FileManager.default.createDirectory(
            at: sourceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let original = #"Text("Summary").accessibilityIdentifier("summary")"#
        try original.write(to: sourceURL, atomically: true, encoding: .utf8)

        let grader = MutationGrader(configuration: MutationGraderConfiguration(
            project: "App.xcodeproj",
            scheme: "App",
            mutations: [
                SourceMutation(
                    path: "Sources/View.swift",
                    replace: #".accessibilityIdentifier("summary")"#,
                    with: #".accessibilityIdentifier("summary-mutated")"#
                ),
            ]
        ))
        let result = try await grader.grade(task: defaultTask(), context: context)

        #expect(!result.passed)
        #expect(result.summary.contains("unmutated tests did not pass"))
        #expect(runner.commands().filter { $0.executable == "/usr/bin/xcodebuild" }.count == 1)
        #expect(try String(contentsOf: sourceURL, encoding: .utf8) == original)
        #expect(result.evidence.contains { $0.name == "mutation-baseline.log" })
    }
}

@Suite("Mutation grader: consistency with the task's test graders")
struct MutationGraderConsistencyTests {
    @Test("Tests the task's UI test grader skips are skipped when challenging the mutation too")
    func inheritsSkippedTests() async throws {
        let runner = FakeProcessRunner()
        runner.setUniversal(exitCode: 0)
        let (context, workspace) = try await makeGradingContext(processRunner: runner)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let sourceURL = workspace.appendingPathComponent("Sources/View.swift")
        try FileManager.default.createDirectory(at: sourceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "let title = \"Settings\"".write(to: sourceURL, atomically: true, encoding: .utf8)

        var task = defaultTask()
        task.graders = [
            .xcuitest(XCUITestGraderConfiguration(scheme: "App", skipTests: ["AppUITests/LegacyTests"])),
        ]
        _ = try await MutationGrader(configuration: MutationGraderConfiguration(
            scheme: "App",
            mutations: [SourceMutation(path: "Sources/View.swift", replace: "\"Settings\"", with: "\"Other\"")]
        )).grade(task: task, context: context)

        let tests = runner.commands().filter { $0.executable == "/usr/bin/xcodebuild" }
        #expect(tests.count == 2)
        #expect(tests.allSatisfy { $0.arguments.contains("-skip-testing:AppUITests/LegacyTests") })
    }

    @Test("The app under test is reset before the baseline and the mutated run")
    func resetsAppStateBeforeEachRun() async throws {
        let runner = FakeProcessRunner()
        runner.setUniversal(exitCode: 0)
        let (context, workspace) = try await makeGradingContext(processRunner: runner, simulatorUDID: "SIM-2")
        defer { try? FileManager.default.removeItem(at: workspace) }
        try writeBuiltApp(named: "Search", bundleID: "com.applebench.Search", in: context.derivedDataURL)
        let sourceURL = workspace.appendingPathComponent("Sources/View.swift")
        try FileManager.default.createDirectory(at: sourceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "results = filter(query)".write(to: sourceURL, atomically: true, encoding: .utf8)

        _ = try await MutationGrader(configuration: MutationGraderConfiguration(
            scheme: "App",
            mutations: [SourceMutation(path: "Sources/View.swift", replace: "filter(query)", with: "[]")]
        )).grade(task: defaultTask(), context: context)

        let calls = runner.commands().map { ([$0.executable] + $0.arguments).joined(separator: " ") }
        let uninstalls = calls.filter { $0 == "/usr/bin/xcrun simctl uninstall SIM-2 com.applebench.Search" }
        #expect(uninstalls.count == 2)
    }
}
