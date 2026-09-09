import AppleBenchCore
import Foundation
import Testing
@testable import AppleBenchGraders

@Suite("Mutation grader")
struct MutationGraderTests {
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
