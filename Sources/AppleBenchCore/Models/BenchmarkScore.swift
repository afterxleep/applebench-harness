import Foundation

/// AppleBench's score: points earned against points available.
///
/// A pass rate answers "how many did it get right" and stops there. Two models
/// can complete the same task and be nothing alike in price and elapsed work.
/// Both are a tick in the same column. Points separate them.
///
/// ```text
/// face value  = 10 points                           the same for every task
/// cost part   = clamp($0.025 / actual cost, 0.25, 1) 80% of adjustment
/// time part   = clamp(300s / active time, 0.25, 1)   20% of adjustment
/// efficiency  = max(0.25, 0.8 × cost + 0.2 × time)   missing telemetry → 0.25
/// points      = passed ? face value × efficiency : 0
/// ```
///
/// Two properties are load-bearing and neither is an accident:
///
/// **A task's points depend on that task alone** — its authored difficulty, its
/// verdict, cost, and active time. Nothing is normalized against the rest of the
/// set, against other models, or against the size of the suite. So the score of
/// two task sets is the sum of their scores, and adding a task set later means
/// running only its own tasks and adding the result to what is already
/// published. Nothing already measured is re-run.
///
/// **Absent telemetry never helps.** A missing cost or active-time component
/// takes the floor rather than full marks, for the same reason exports leave a
/// missing cost blank instead of writing `$0.00`: filling absence with the
/// favorable value would make a model look better the worse its reporting is.
///
/// The constants are authored, frozen under a spec id, and stated on the site.
/// Changing one is a scoring revision — every published number is recomputed
/// from its stored export, which does not require re-running any benchmark.
public enum AppleBenchScore {
    /// The frozen scoring specification these constants belong to. Published
    /// numbers are only comparable within one, the same way a pass rate is only
    /// comparable within one suite revision.
    public static let specification = "points-v3"

    /// What every task is worth. The same for all of them.
    ///
    /// Face value used to be ten points per step of authored difficulty. That
    /// weighted the score by a judgment nobody had checked, and checking it
    /// showed it was wrong per task: three tasks rated 6 were solved in under
    /// 1,200 tokens while tasks rated 1 cost twenty times that. Weighting by
    /// it paid sixty points for a one-line fix and ten for an afternoon's
    /// work.
    ///
    /// Difficulty is still recorded on a task, because it says something to a
    /// reader choosing what to look at. It no longer decides what a solve is
    /// worth. What remains in the score is measured: the task was solved, and
    /// what it cost to solve it.
    public static let pointsPerTask = 10

    /// Clean values just above the observed 75th percentiles for successful
    /// runs ($0.022 and 275 active seconds). Cost dominates because it captures
    /// the real resource tradeoff even when a provider makes tokens cheap.
    public static let referenceCostUSD = 0.025
    public static let referenceActiveTimeSeconds = 300.0
    public static let costWeight = 0.8
    public static let activeTimeWeight = 0.2

    /// The least a verified solve can be worth, as a fraction of face value.
    /// A wasteful solve must still outscore a failure: it did the work.
    public static let minimumEfficiency = 0.25

    /// What a task is worth when solved at or under the allowance.
    ///
    /// Every task, whatever it is. A suite's available points are therefore
    /// just its size, which makes a score readable without knowing how any
    /// task was rated.
    public static func faceValue() -> Int { pointsPerTask }

    private static func componentEfficiency(value: Double?, reference: Double) -> Double {
        guard let value, value >= 0 else { return minimumEfficiency }
        guard value > reference else { return 1 }
        return max(minimumEfficiency, reference / value)
    }

    /// The fraction of face value a solve keeps, given its price and observed
    /// active agent time. A genuinely free run is efficient; missing cost is
    /// represented by `nil` and is conservative instead.
    public static func efficiency(costUSD: Double?, activeTimeSeconds: Double?) -> Double {
        let cost = componentEfficiency(value: costUSD, reference: referenceCostUSD)
        let time = componentEfficiency(value: activeTimeSeconds, reference: referenceActiveTimeSeconds)
        return max(minimumEfficiency, costWeight * cost + activeTimeWeight * time)
    }

    /// Points earned by one run. A failure earns nothing; its face value still
    /// counts toward what was available.
    public static func points(passed: Bool, costUSD: Double?, activeTimeSeconds: Double?) -> Double {
        guard passed else { return 0 }
        return Double(faceValue()) * efficiency(costUSD: costUSD, activeTimeSeconds: activeTimeSeconds)
    }

    public static func points(for result: BenchmarkRunResult) -> Double {
        points(
            passed: result.result.passed,
            costUSD: result.usage.estimatedCostUSD,
            activeTimeSeconds: result.metrics?.agentDurationSeconds
        )
    }

    /// Sums a set of runs. Because every term is independent, `total(for: a) +
    /// total(for: b)` is `total(for: a + b)`.
    public static func total(for results: [BenchmarkRunResult]) -> Total {
        Total(results: results)
    }

    public struct Total: Sendable, Encodable, Equatable {
        /// The spec the numbers were computed under.
        public var specification: String
        public var points: Double
        public var available: Int
        /// Runs included in the score.
        public var scoredRuns: Int
        /// Reserved for report compatibility; every current run is scorable.
        public var unscoredRuns: Int
        public var solvesWithUnreportedCost: Int
        public var solvesWithUnreportedActiveTime: Int
        public var referenceCostUSD: Double
        public var referenceActiveTimeSeconds: Double
        public var costWeight: Double
        public var activeTimeWeight: Double
        public var minimumEfficiency: Double

        public var fractionOfAvailable: Double {
            available > 0 ? points / Double(available) : 0
        }

        enum CodingKeys: String, CodingKey {
            case specification, points, available
            case fractionOfAvailable = "fraction_of_available"
            case scoredRuns = "scored_runs"
            case unscoredRuns = "unscored_runs"
            case solvesWithUnreportedCost = "solves_with_unreported_cost"
            case solvesWithUnreportedActiveTime = "solves_with_unreported_active_time"
            case referenceCostUSD = "reference_cost_usd"
            case referenceActiveTimeSeconds = "reference_active_time_seconds"
            case costWeight = "cost_weight"
            case activeTimeWeight = "active_time_weight"
            case minimumEfficiency = "minimum_efficiency"
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(specification, forKey: .specification)
            try container.encode(points, forKey: .points)
            try container.encode(available, forKey: .available)
            try container.encode(fractionOfAvailable, forKey: .fractionOfAvailable)
            try container.encode(scoredRuns, forKey: .scoredRuns)
            try container.encode(unscoredRuns, forKey: .unscoredRuns)
            try container.encode(solvesWithUnreportedCost, forKey: .solvesWithUnreportedCost)
            try container.encode(solvesWithUnreportedActiveTime, forKey: .solvesWithUnreportedActiveTime)
            try container.encode(referenceCostUSD, forKey: .referenceCostUSD)
            try container.encode(referenceActiveTimeSeconds, forKey: .referenceActiveTimeSeconds)
            try container.encode(costWeight, forKey: .costWeight)
            try container.encode(activeTimeWeight, forKey: .activeTimeWeight)
            try container.encode(minimumEfficiency, forKey: .minimumEfficiency)
        }

        init(results: [BenchmarkRunResult]) {
            specification = AppleBenchScore.specification
            referenceCostUSD = AppleBenchScore.referenceCostUSD
            referenceActiveTimeSeconds = AppleBenchScore.referenceActiveTimeSeconds
            costWeight = AppleBenchScore.costWeight
            activeTimeWeight = AppleBenchScore.activeTimeWeight
            minimumEfficiency = AppleBenchScore.minimumEfficiency

            var earned = 0.0
            var possible = 0
            var scored = 0
            let unscored = 0
            var solvesMissingCost = 0
            var solvesMissingTime = 0
            // Every run is scorable now. Nothing is excluded for lacking an
            // authored difficulty, because nothing is weighted by one.
            for result in results {
                scored += 1
                possible += AppleBenchScore.faceValue()
                earned += AppleBenchScore.points(for: result)
                if result.result.passed, result.usage.estimatedCostUSD == nil {
                    solvesMissingCost += 1
                }
                if result.result.passed, result.metrics?.agentDurationSeconds == nil {
                    solvesMissingTime += 1
                }
            }
            points = earned
            available = possible
            scoredRuns = scored
            unscoredRuns = unscored
            solvesWithUnreportedCost = solvesMissingCost
            solvesWithUnreportedActiveTime = solvesMissingTime
        }
    }
}
