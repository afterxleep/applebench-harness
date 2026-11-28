import Foundation
import Testing
@testable import AppleBenchAgents
@testable import AppleBenchCore

/// Emits one usage event per line, reporting the number in the line.
private struct StubUsageParser: AgentOutputParser {
    func parse(line: String) -> ParsedAgentEvent? {
        guard let value = Int(line.trimmingCharacters(in: .whitespaces)) else { return nil }
        return ParsedAgentEvent(
            kind: .usage,
            payload: .object([:]),
            usage: AgentUsage(totalTokens: value)
        )
    }
}

@Suite("Token budget")
struct TokenBudgetTests {
    @Test("Per-step reports are summed, matching how totals are accounted after a run")
    func sumsSteps() async {
        let budget = TokenBudget(cap: 1_000, parser: StubUsageParser())
        await budget.consume("100\n200\n300\n")
        #expect(await budget.spent == 600)
        #expect(await budget.isExceeded == false)
    }

    @Test("A chunk that splits a line mid-number does not lose or double the count")
    func handlesSplitLines() async {
        let budget = TokenBudget(cap: 1_000, parser: StubUsageParser())
        await budget.consume("12")
        await budget.consume("3\n45")
        await budget.consume("6\n")
        // 123 + 456, not 12 + 3 + 45 + 6 and not 123 counted twice.
        #expect(await budget.spent == 579)
    }

    @Test("Crossing the cap trips the budget")
    func tripsOnCap() async {
        let budget = TokenBudget(cap: 250, parser: StubUsageParser())
        await budget.consume("100\n")
        #expect(await budget.isExceeded == false)
        await budget.consume("200\n")
        #expect(await budget.isExceeded == true)
        #expect(await budget.spent == 300)
    }

    @Test("A line the parser does not understand is ignored rather than counted as zero")
    func ignoresUnparsedLines() async {
        let budget = TokenBudget(cap: 1_000, parser: StubUsageParser())
        await budget.consume("hello\n100\nnot json\n")
        #expect(await budget.spent == 100)
    }

    @Test("A trailing line with no newline is not counted until it is complete")
    func waitsForCompleteLines() async {
        let budget = TokenBudget(cap: 1_000, parser: StubUsageParser())
        await budget.consume("100\n99")
        // Counting "99" now would be wrong: the next chunk may make it 990.
        #expect(await budget.spent == 100)
        await budget.consume("0\n")
        #expect(await budget.spent == 1_090)
    }
}
