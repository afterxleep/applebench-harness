import Foundation
import Testing
@testable import AppleBenchCore

@Suite("Run limit caps")
struct LimitCapsTests {
    @Test("A cap lowers a task that asks for more")
    func lowersLargerTimeout() {
        let limits = RunLimits(timeoutSeconds: 1_800).capped(by: LimitCaps(timeoutSeconds: 600))
        #expect(limits.timeoutSeconds == 600)
    }

    @Test("A cap never raises a task that asks for less")
    func neverRaisesSmallerTimeout() {
        // Raising it would hand a task more room than its author gave it,
        // which changes what the task measures.
        let limits = RunLimits(timeoutSeconds: 300).capped(by: LimitCaps(timeoutSeconds: 900))
        #expect(limits.timeoutSeconds == 300)
    }

    @Test("A token cap applies to a task that declares no budget")
    func appliesTokenCapToUnbudgetedTask() {
        let limits = RunLimits(timeoutSeconds: 900).capped(by: LimitCaps(maxTokens: 50_000))
        #expect(limits.maxTokens == 50_000)
    }

    @Test("A token cap tightens a larger budget and leaves a smaller one alone")
    func tokenCapOnlyTightens() {
        let loose = RunLimits(timeoutSeconds: 900, maxTokens: 200_000)
        #expect(loose.capped(by: LimitCaps(maxTokens: 50_000)).maxTokens == 50_000)

        let tight = RunLimits(timeoutSeconds: 900, maxTokens: 10_000)
        #expect(tight.capped(by: LimitCaps(maxTokens: 50_000)).maxTokens == 10_000)
    }

    @Test("No caps leaves the task's own limits untouched")
    func noCapsIsIdentity() {
        let limits = RunLimits(timeoutSeconds: 900, maxCostUSD: 5, maxTokens: 100_000)
        #expect(limits.capped(by: LimitCaps()) == limits)
    }
}

@Suite("Default limit caps")
struct DefaultLimitCapsTests {
    @Test("Time is capped by default and tokens are not")
    func defaultsCapTimeOnly() {
        // A token default would have to be guessed: the only measurements are
        // from one model on the easier sample suite, and one set too low
        // truncates real work while reporting an ordinary failure.
        #expect(LimitCaps.standard.timeoutSeconds == 1_200)
        #expect(LimitCaps.standard.maxTokens == nil)
    }

    @Test("The default tightens the long outliers and leaves the rest alone")
    func defaultTightensOutliersOnly() {
        // The tasks written at 1500s and 1800s come down to 20 minutes; the
        // 900s majority is untouched, so what those tasks measure is unchanged.
        #expect(RunLimits(timeoutSeconds: 1_800).capped(by: .standard).timeoutSeconds == 1_200)
        #expect(RunLimits(timeoutSeconds: 1_500).capped(by: .standard).timeoutSeconds == 1_200)
        #expect(RunLimits(timeoutSeconds: 900).capped(by: .standard).timeoutSeconds == 900)
    }

    @Test("A task asking for less than the default keeps its own limit")
    func defaultsOnlyTighten() {
        let short = RunLimits(timeoutSeconds: 600, maxTokens: 5_000)
        #expect(short.capped(by: .standard) == short)
    }
}
