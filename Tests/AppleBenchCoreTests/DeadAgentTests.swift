import Foundation
import Testing
@testable import AppleBenchCore

/// A dead agent is an infrastructure fault wearing a model's score.
///
/// When the agent process dies before it can start, every task still builds,
/// still runs its tests against an untouched fixture, and still records an
/// honest-looking FAIL. A suite of those reads as a model that solved nothing.
/// Telling the two apart is the difference between a result and a bug.
@Suite("Dead agent detection")
struct DeadAgentTests {
    private func result(
        termination: AgentTerminationReason,
        exitCode: Int32?,
        tokens: Int? = nil,
        finalResponse: String? = nil
    ) -> AgentRunResult {
        var usage = AgentUsage()
        usage.totalTokens = tokens
        return AgentRunResult(
            metadata: AgentMetadata(agent: "opencode", model: "m", version: nil, configuration: [:]),
            terminationReason: termination,
            exitCode: exitCode,
            usage: usage,
            finalResponse: finalResponse
        )
    }

    @Test("An agent that exits nonzero having produced nothing never ran")
    func nonzeroExitWithNoOutputNeverRan() {
        #expect(result(termination: .failed, exitCode: 1).neverRan)
    }

    @Test("Spending tokens proves the agent ran, however it ended")
    func tokensProveItRan() {
        #expect(!result(termination: .failed, exitCode: 1, tokens: 12).neverRan)
    }

    @Test("A final response proves the agent ran")
    func aResponseProvesItRan() {
        #expect(!result(termination: .failed, exitCode: 1, finalResponse: "I gave up").neverRan)
    }

    @Test("A clean exit is never treated as a dead agent")
    func cleanExitIsNotDead() {
        #expect(!result(termination: .completed, exitCode: 0).neverRan)
    }

    @Test("A timeout or a budget stop is a model outcome, not a dead agent")
    func stoppedRunsAreModelOutcomes() {
        // Both are the harness stopping a model that was working. Scoring them
        // as infrastructure would erase a real, and interesting, failure.
        #expect(!result(termination: .timeout, exitCode: nil).neverRan)
        #expect(!result(termination: .budgetExceeded, exitCode: nil).neverRan)
    }
}
