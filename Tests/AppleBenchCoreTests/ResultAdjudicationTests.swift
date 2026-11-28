import Foundation
import Testing
@testable import AppleBenchCore

@Suite("Result adjudication")
struct ResultAdjudicationTests {
    @Test("A documented grader correction changes aggregation without rewriting the original result")
    func appliesGraderCorrection() throws {
        let original = makeResult()
        let adjudication = ResultAdjudication(
            sourceRunID: original.runID,
            reason: "The first UI action was ignored; the recorded final tree satisfies the corrected passive assertion.",
            evidence: ["logs/uiflow-tree.json"],
            graders: [
                .init(index: 0, name: "uiflow", passed: true, summary: "2 UI assertions hold in default"),
            ]
        )

        let corrected = try adjudication.applying(to: original)

        #expect(original.result.passed == false)
        #expect(original.graders[0].passed == false)
        #expect(corrected.result.passed == true)
        #expect(corrected.graders.map(\.passed) == [true, true])
        #expect(corrected.graders[0].summary == "2 UI assertions hold in default")
        #expect(corrected.agent == original.agent)
        #expect(corrected.usage == original.usage)
    }

    @Test("Aggregation discovers an adjudication beside result.json")
    func readsSiblingAdjudication() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("applebench-adjudication-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = makeResult()
        let resultURL = directory.appendingPathComponent("result.json")
        try original.write(to: resultURL)
        try ResultAdjudication(
            sourceRunID: original.runID,
            reason: "Recorded evidence satisfies the corrected assertion.",
            evidence: ["logs/uiflow-tree.json"],
            graders: [.init(index: 0, name: "uiflow", passed: true, summary: "corrected")]
        ).write(to: directory.appendingPathComponent("adjudication.json"))

        let aggregated = try BenchmarkRunResult.readForAggregation(from: resultURL)

        #expect(aggregated.result.passed)
        #expect(aggregated.graders[0].summary == "corrected")
        #expect(try BenchmarkRunResult.read(from: resultURL) == original)
    }

    @Test("An adjudication cannot be applied to a different run")
    func rejectsDifferentRun() {
        let adjudication = ResultAdjudication(
            sourceRunID: "another-run",
            reason: "Wrong source",
            evidence: [],
            graders: []
        )

        #expect(throws: ResultAdjudication.Error.sourceRunMismatch) {
            try adjudication.applying(to: makeResult())
        }
    }

    @Test("A grader correction identifies both its position and grader name")
    func rejectsWrongGrader() {
        let original = makeResult()
        let adjudication = ResultAdjudication(
            sourceRunID: original.runID,
            reason: "Wrong grader",
            evidence: [],
            graders: [.init(index: 0, name: "build", passed: true, summary: "ok")]
        )

        #expect(throws: ResultAdjudication.Error.graderMismatch) {
            try adjudication.applying(to: original)
        }
    }

    private func makeResult() -> BenchmarkRunResult {
        BenchmarkRunResult(
            runID: "2026-09-09T141135-g2-order-002-opencode",
            task: "g2-order-002",
            category: .interaction,
            difficulty: 9,
            tags: ["deletion"],
            agent: AgentMetadata(agent: "opencode", model: "openrouter/z-ai/glm-5.3-flash"),
            environment: .init(macos: "26.5", architecture: "arm64", xcode: "27.0", xcodeBuild: "27A1"),
            result: .init(passed: false, durationSeconds: 42, agentTermination: .completed),
            usage: AgentUsage(inputTokens: 10, outputTokens: 5, totalTokens: 15),
            metrics: nil,
            graders: [
                .init(name: "uiflow", passed: false, durationSeconds: 1, summary: "tap failed", evidence: []),
                .init(name: "uiflow", passed: true, durationSeconds: 1, summary: "flow passed", evidence: []),
            ],
            git: .init(baseCommit: "abc", filesChanged: 1, insertions: 2, deletions: 1),
            artifacts: .init(events: "events.jsonl", diff: "diff.patch", logs: "logs")
        )
    }
}
