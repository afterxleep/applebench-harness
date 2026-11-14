import Foundation
import Testing
@testable import AppleBenchCore

@Suite("Attempt selection")
struct AttemptSelectionTests {
    private func makeResult(
        runID: String,
        task: String,
        passed: Bool,
        model: String = "vendor/model-1"
    ) -> BenchmarkRunResult {
        BenchmarkRunResult(
            runID: runID,
            task: task,
            category: .ops,
            difficulty: 5,
            tags: [],
            agent: AgentMetadata(agent: "opencode", model: model),
            environment: .init(macos: "27.0", architecture: "arm64", xcode: "27.0", xcodeBuild: "27A1"),
            result: .init(passed: passed, durationSeconds: 1, agentTermination: .completed),
            usage: AgentUsage(totalTokens: 1000),
            metrics: nil,
            graders: [],
            git: .init(baseCommit: "abc123", filesChanged: 1, insertions: 1, deletions: 0),
            artifacts: .init(events: "events.jsonl")
        )
    }

    private var threeAttempts: [BenchmarkRunResult] {
        // Deliberately out of order: selection must not depend on the order the
        // filesystem enumerator happened to return.
        [
            makeResult(runID: "2026-09-01T170000-ops-004-opencode", task: "ops-004", passed: true),
            makeResult(runID: "2026-09-01T150000-ops-004-opencode", task: "ops-004", passed: false),
            makeResult(runID: "2026-09-02T050000-ops-004-opencode", task: "ops-004", passed: false),
        ]
    }

    @Test("Every run counts when no rule is applied")
    func allKeepsEveryRun() {
        #expect(AttemptSelection.all.apply(to: threeAttempts).count == 3)
    }

    @Test("First takes the earliest run id, not the first one found")
    func firstIsDeterministic() {
        let selected = AttemptSelection.first.apply(to: threeAttempts)
        #expect(selected.count == 1)
        #expect(selected[0].runID == "2026-09-01T150000-ops-004-opencode")
    }

    @Test("Latest takes the most recent run id")
    func latestIsDeterministic() {
        let selected = AttemptSelection.latest.apply(to: threeAttempts)
        #expect(selected[0].runID == "2026-09-02T050000-ops-004-opencode")
    }

    @Test("Best takes the earliest passing run, and the earliest run when none passed")
    func bestPrefersAPass() {
        let selected = AttemptSelection.best.apply(to: threeAttempts)
        #expect(selected[0].runID == "2026-09-01T170000-ops-004-opencode")

        let allFailed = threeAttempts.map { result -> BenchmarkRunResult in
            var copy = result
            copy.result.passed = false
            return copy
        }
        #expect(AttemptSelection.best.apply(to: allFailed)[0].runID == "2026-09-01T150000-ops-004-opencode")
    }

    @Test("Two models attempting the same task are never collapsed into one")
    func selectionIsPerConfiguration() {
        // Selecting per task alone would let a second model's run supersede the
        // first model's, silently deleting one of them from the export.
        let runs = [
            makeResult(runID: "2026-09-01T150000-ops-004-opencode", task: "ops-004", passed: true, model: "a/model"),
            makeResult(runID: "2026-09-01T160000-ops-004-opencode", task: "ops-004", passed: true, model: "z/model"),
        ]
        let selected = AttemptSelection.latest.apply(to: runs)
        #expect(selected.count == 2)
        #expect(Set(selected.map { $0.agent.model }) == ["a/model", "z/model"])
    }

    @Test("Distinct tasks all survive every rule")
    func distinctTasksSurvive() {
        let runs = [
            makeResult(runID: "2026-09-01T150000-ops-004-opencode", task: "ops-004", passed: true),
            makeResult(runID: "2026-09-01T160000-build-002-opencode", task: "build-002", passed: false),
        ]
        for rule in AttemptSelection.allCases {
            #expect(rule.apply(to: runs).count == 2)
        }
    }
}
