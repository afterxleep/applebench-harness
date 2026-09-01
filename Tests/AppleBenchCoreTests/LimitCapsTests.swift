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
