import Foundation
import Testing
@testable import AppleBenchCore

@Suite("Result collection")
struct ResultCollectionTests {
    @Test("Live adjudicated runs replace the same immutable run from a base report")
    func mergesBaseReportWithLiveRuns() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("applebench-base-report-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let old = makeResult(runID: "run-1", task: "task-1", passed: false)
        let untouched = makeResult(runID: "run-2", task: "task-2", passed: true)
        let reportURL = directory.appendingPathComponent("report.json")
        try ResultsExport.json(for: [old, untouched]).write(to: reportURL)

        let corrected = makeResult(runID: "run-1", task: "task-1", passed: true)
        let merged = try ResultCollection.merged(baseReports: [reportURL], live: [corrected])

        #expect(merged.count == 2)
        #expect(merged.first { $0.runID == "run-1" }?.result.passed == true)
        #expect(merged.first { $0.runID == "run-2" }?.result.passed == true)
    }

    private func makeResult(runID: String, task: String, passed: Bool) -> BenchmarkRunResult {
        BenchmarkRunResult(
            runID: runID,
            task: task,
            category: .build,
            difficulty: 1,
            agent: AgentMetadata(agent: "opencode", model: "vendor/model"),
            environment: .init(macos: "26.5", architecture: "arm64", xcode: "27.0", xcodeBuild: "27A1"),
            result: .init(passed: passed, durationSeconds: 1, agentTermination: .completed),
            usage: AgentUsage(totalTokens: 10),
            metrics: nil,
            graders: [.init(name: "build", passed: passed, durationSeconds: 1, summary: "result", evidence: [])],
            git: .init(baseCommit: "abc", filesChanged: 1, insertions: 1, deletions: 0),
            artifacts: .init(events: "events.jsonl")
        )
    }
}
