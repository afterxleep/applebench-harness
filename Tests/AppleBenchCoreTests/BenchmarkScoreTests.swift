import Foundation
import Testing
@testable import AppleBenchCore

@Suite("AppleBench points")
struct BenchmarkScoreTests {
    private func makeResult(
        task: String,
        difficulty: Int? = 5,
        passed: Bool = true,
        costUSD: Double? = 0.01,
        activeTimeSeconds: Double? = 120
    ) -> BenchmarkRunResult {
        var metrics = TrajectoryMetrics(events: [])
        metrics.agentDurationSeconds = activeTimeSeconds
        return BenchmarkRunResult(
            runID: "2026-01-01T000000-\(task)-opencode",
            task: task,
            category: .build,
            difficulty: difficulty,
            tags: [],
            agent: AgentMetadata(agent: "opencode", model: "vendor/model-1"),
            environment: .init(macos: "27.0", architecture: "arm64", xcode: "27.0", xcodeBuild: "27A1"),
            result: .init(passed: passed, durationSeconds: 1, agentTermination: .completed),
            usage: AgentUsage(totalTokens: 10_000, estimatedCostUSD: costUSD),
            metrics: metrics,
            graders: [],
            git: .init(baseCommit: "abc123", filesChanged: 1, insertions: 1, deletions: 0),
            artifacts: .init(events: "events.jsonl")
        )
    }

    @Test("Every task is worth the same")
    func faceValueIsFlat() {
        // Face value was ten points per step of authored difficulty, which
        // weighted the score by a judgment that turned out wrong per task:
        // tasks rated 6 fell in under 1,200 tokens while tasks rated 1 cost
        // twenty times that. What a solve is worth no longer depends on
        // anyone's estimate of how hard it was.
        #expect(AppleBenchScore.faceValue() == AppleBenchScore.pointsPerTask)
    }

    @Test("A solve inside the cost and time allowances keeps its full face value")
    func solvesInsideBudgetScoreInFull() {
        #expect(AppleBenchScore.efficiency(costUSD: 0.001, activeTimeSeconds: 1) == 1)
        #expect(AppleBenchScore.efficiency(
            costUSD: AppleBenchScore.referenceCostUSD,
            activeTimeSeconds: AppleBenchScore.referenceActiveTimeSeconds
        ) == 1)
        #expect(AppleBenchScore.points(passed: true, costUSD: 0.01, activeTimeSeconds: 120)
            == Double(AppleBenchScore.pointsPerTask))
    }

    @Test("Cost dominates the efficiency adjustment")
    func costDominatesEfficiency() {
        let cost = AppleBenchScore.referenceCostUSD * 2
        let efficiency = AppleBenchScore.efficiency(costUSD: cost, activeTimeSeconds: 1)
        #expect(abs(efficiency - 0.6) < 0.0001)
        #expect(abs(AppleBenchScore.points(passed: true, costUSD: cost, activeTimeSeconds: 1) - 6) < 0.0001)
    }

    @Test("A wasteful solve still outscores a failure, down to the floor")
    func efficiencyIsFloored() {
        #expect(AppleBenchScore.efficiency(costUSD: 100, activeTimeSeconds: 100_000)
            == AppleBenchScore.minimumEfficiency)
        #expect(AppleBenchScore.points(passed: true, costUSD: 100, activeTimeSeconds: 100_000) > 0)
    }

    @Test("Unreported cost and time take the floor rather than full marks")
    func absentUsageNeverImprovesTheScore() {
        #expect(AppleBenchScore.efficiency(costUSD: nil, activeTimeSeconds: nil)
            == AppleBenchScore.minimumEfficiency)
        #expect(AppleBenchScore.efficiency(costUSD: 0, activeTimeSeconds: 0) == 1)
    }

    @Test("A failed task scores nothing but still costs its face value")
    func failuresScoreZeroAndStayInTheDenominator() {
        #expect(AppleBenchScore.points(passed: false, costUSD: 0.001, activeTimeSeconds: 1) == 0)

        let total = AppleBenchScore.total(for: [
            makeResult(task: "build-001", difficulty: 9, passed: false)
        ])
        #expect(total.points == 0)
        #expect(total.available == AppleBenchScore.pointsPerTask)
    }

    @Test("A run with no authored difficulty is scored like any other")
    func everyRunIsScorable() {
        // Nothing is set aside for lacking a difficulty, because nothing is
        // weighted by one.
        let total = AppleBenchScore.total(for: [
            makeResult(task: "adhoc-001", difficulty: nil),
            makeResult(task: "build-001", difficulty: 3),
        ])
        #expect(total.scoredRuns == 2)
        #expect(total.unscoredRuns == 0)
        #expect(total.available == 2 * AppleBenchScore.pointsPerTask)
    }

    @Test("Scoring two sets separately and adding them equals scoring the union")
    func scoreIsAdditiveAcrossTaskSets() {
        // The property the whole design rests on: a later task set is scored by
        // running only its own tasks and adding the result to what is already
        // published. If this ever stops holding, every published total has to
        // be re-run instead.
        let gold = [
            makeResult(task: "build-001", difficulty: 3, passed: true, costUSD: 0.012),
            makeResult(task: "ops-001", difficulty: 6, passed: false, costUSD: 0.40),
        ]
        let goldTwo = [
            makeResult(task: "widget-001", difficulty: 8, passed: true, costUSD: 0.15),
            makeResult(task: "swiftdata-001", difficulty: 2, passed: true, costUSD: nil),
        ]

        let first = AppleBenchScore.total(for: gold)
        let second = AppleBenchScore.total(for: goldTwo)
        let union = AppleBenchScore.total(for: gold + goldTwo)

        #expect(abs((first.points + second.points) - union.points) < 0.0001)
        #expect(first.available + second.available == union.available)
        #expect(first.scoredRuns + second.scoredRuns == union.scoredRuns)
    }

    @Test("An empty set scores nothing rather than dividing by zero")
    func emptySetIsSafe() {
        let total = AppleBenchScore.total(for: [])
        #expect(total.points == 0)
        #expect(total.available == 0)
        #expect(total.fractionOfAvailable == 0)
    }
}
