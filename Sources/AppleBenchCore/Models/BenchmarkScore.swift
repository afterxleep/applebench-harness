import Foundation

/// AppleBench's score: points earned against points available.
///
/// A pass rate answers "how many did it get right" and stops there. Two models
/// can complete the same task and be nothing alike — one reads the build log
/// and edits two lines, the other rebuilds the project eleven times and burns
/// three quarters of a million tokens arriving at the same diff. Both are a
/// tick in the same column. Points separate them.
///
/// ```text
/// face value  = 10 × difficulty                     difficulty 1–10 → 10–100 points
/// budget      = 50,000 total tokens                 flat, the same for every task
/// efficiency  = clamp(budget / tokens, 0.25, 1.0)   unreported tokens → 0.25
/// points      = passed ? face value × efficiency : 0
/// ```
///
/// Two properties are load-bearing and neither is an accident:
///
/// **A task's points depend on that task alone** — its authored difficulty, its
/// verdict, and its token spend. Nothing is normalized against the rest of the
/// set, against other models, or against the size of the suite. So the score of
/// two task sets is the sum of their scores, and adding a task set later means
/// running only its own tasks and adding the result to what is already
/// published. Nothing already measured is re-run.
///
/// **Absent telemetry never helps.** A solve that reported no token usage takes
/// the floor rather than full marks, for the same reason the exports leave a
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
    public static let specification = "points-v2"

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

    /// The token allowance a solve may spend before it starts losing points.
    ///
    /// Flat, not scaled by difficulty. Measured spend does not track authored
    /// difficulty — across the first scored run the median solve cost between
    /// 14k and 26k tokens at every difficulty from 1 to 7 — so scaling the
    /// allowance by difficulty would encode a relationship the data does not
    /// show. Difficulty scales the reward; the allowance is the same for every
    /// task. It sits above the 75th percentile of observed solves, so ordinary
    /// work is not penalized and only genuine overspend is.
    public static let referenceTokenBudget = 50_000

    /// The least a verified solve can be worth, as a fraction of face value.
    /// A wasteful solve must still outscore a failure: it did the work.
    public static let minimumEfficiency = 0.25

    /// What a task is worth when solved at or under the allowance.
    ///
    /// Every task, whatever it is. A suite's available points are therefore
    /// just its size, which makes a score readable without knowing how any
    /// task was rated.
    public static func faceValue() -> Int { pointsPerTask }

    /// The fraction of face value a solve keeps, given what it spent.
    public static func efficiency(totalTokens: Int?) -> Double {
        guard let totalTokens, totalTokens > 0 else { return minimumEfficiency }
        guard totalTokens > referenceTokenBudget else { return 1 }
        let ratio = Double(referenceTokenBudget) / Double(totalTokens)
        return max(minimumEfficiency, ratio)
    }

    /// Points earned by one run. A failure earns nothing; its face value still
    /// counts toward what was available.
    public static func points(passed: Bool, totalTokens: Int?) -> Double {
        guard passed else { return 0 }
        return Double(faceValue()) * efficiency(totalTokens: totalTokens)
    }

    public static func points(for result: BenchmarkRunResult) -> Double {
        points(passed: result.result.passed, totalTokens: result.usage.totalTokens)
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
        /// Runs that had an authored difficulty and could therefore be scored.
        public var scoredRuns: Int
        /// Runs with no authored difficulty, excluded from both sides.
        public var unscoredRuns: Int
        /// Solves counted at the floor because the agent reported no usage.
        public var solvesWithUnreportedTokens: Int
        public var referenceTokenBudget: Int
        public var minimumEfficiency: Double

        public var fractionOfAvailable: Double {
            available > 0 ? points / Double(available) : 0
        }

        enum CodingKeys: String, CodingKey {
            case specification, points, available
            case fractionOfAvailable = "fraction_of_available"
            case scoredRuns = "scored_runs"
            case unscoredRuns = "unscored_runs"
            case solvesWithUnreportedTokens = "solves_with_unreported_tokens"
            case referenceTokenBudget = "reference_token_budget"
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
            try container.encode(solvesWithUnreportedTokens, forKey: .solvesWithUnreportedTokens)
            try container.encode(referenceTokenBudget, forKey: .referenceTokenBudget)
            try container.encode(minimumEfficiency, forKey: .minimumEfficiency)
        }

        init(results: [BenchmarkRunResult]) {
            specification = AppleBenchScore.specification
            referenceTokenBudget = AppleBenchScore.referenceTokenBudget
            minimumEfficiency = AppleBenchScore.minimumEfficiency

            var earned = 0.0
            var possible = 0
            var scored = 0
            var unscored = 0
            var blindSolves = 0
            // Every run is scorable now. Nothing is excluded for lacking an
            // authored difficulty, because nothing is weighted by one.
            for result in results {
                scored += 1
                possible += AppleBenchScore.faceValue()
                earned += AppleBenchScore.points(for: result)
                if result.result.passed, (result.usage.totalTokens ?? 0) <= 0 {
                    blindSolves += 1
                }
            }
            points = earned
            available = possible
            scoredRuns = scored
            unscoredRuns = unscored
            solvesWithUnreportedTokens = blindSolves
        }
    }
}
