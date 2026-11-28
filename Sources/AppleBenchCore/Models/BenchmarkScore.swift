import Foundation

/// AppleBench's empirical capability score.
///
/// Task weights come from how the complete published models actually
/// performed, not from an authored rubric. A task that every included model
/// passes is worth 100 points; the rarer a pass is, the more the task is
/// worth, up to a 2000-point cap. A model earns a task's full weight when it
/// passes and zero when it fails.
///
/// ```text
/// task weight      = min(2000, round(100 × modelCount / passingModelCount))
///                    (a task no model passes is worth the 2000-point cap)
/// task points      = passed ? weight : 0
/// available points = sum(task weight)
/// score percentage = 100 × earned points / available points
/// ```
///
/// The authored `difficulty` stays in run metadata but has no effect on the
/// score. Weights are derived from complete runs of the current suite only,
/// so adding a complete model can change every task's weight — previously
/// published models are rescored without being rerun. That makes the score a
/// living number for a suite revision, which is why every export records the
/// specification and the weights it used.
///
/// Cost, tokens, and time never change capability points. They remain separate
/// measurements and can be divided by earned points when comparing efficiency.
public enum AppleBenchScore {
    /// Published scores are only comparable within the same scoring spec and
    /// suite revision.
    public static let specification = "empirical-v1"
    /// The points a task is worth when every included model passes it.
    public static let baseTaskWeight = 100
    /// The most any single task can be worth, however rare its passes.
    public static let maximumTaskWeight = 2000

    /// The empirical weight of a task seen by `modelCount` models of which
    /// `passingModelCount` passed it. `nil` when the counts cannot describe a
    /// real measurement; a task no model passed earns the cap, not zero.
    public static func weight(modelCount: Int, passingModelCount: Int) -> Int? {
        guard modelCount > 0, passingModelCount >= 0, passingModelCount <= modelCount else { return nil }
        guard passingModelCount > 0 else { return maximumTaskWeight }
        let exact = Double(baseTaskWeight * modelCount) / Double(passingModelCount)
        return min(maximumTaskWeight, Int(exact.rounded()))
    }

    /// Empirical weights for every task in a set of complete runs, keyed by
    /// task identifier. Each entry in `runsByModel` is one complete model run;
    /// a task only a subset of models ran is weighted by that subset.
    public static func weights(for runsByModel: [String: [BenchmarkRunResult]]) -> [String: Int] {
        var modelCounts: [String: Int] = [:]
        var passingCounts: [String: Int] = [:]
        for runs in runsByModel.values {
            for result in runs {
                modelCounts[result.task, default: 0] += 1
                if result.result.passed {
                    passingCounts[result.task, default: 0] += 1
                }
            }
        }
        var weights: [String: Int] = [:]
        for (task, modelCount) in modelCounts {
            if let weight = weight(modelCount: modelCount, passingModelCount: passingCounts[task] ?? 0) {
                weights[task] = weight
            }
        }
        return weights
    }

    /// Points earned by one task under its empirical weight. A task with no
    /// weight is unscored and returns `nil`; a scored failure returns zero.
    public static func points(passed: Bool, weight: Int?) -> Int? {
        guard let weight, weight > 0 else { return nil }
        return passed ? weight : 0
    }

    public static func points(for result: BenchmarkRunResult, weights: [String: Int]) -> Int? {
        points(passed: result.result.passed, weight: weights[result.task])
    }

    public static func total(for results: [BenchmarkRunResult], weights: [String: Int]) -> Total {
        Total(results: results, weights: weights)
    }

    public struct Total: Sendable, Encodable, Equatable {
        public var specification: String
        public var points: Int
        public var available: Int
        public var scoredRuns: Int
        public var unscoredRuns: Int

        public var fractionOfAvailable: Double {
            available > 0 ? Double(points) / Double(available) : 0
        }

        public var percentage: Double {
            fractionOfAvailable * 100
        }

        enum CodingKeys: String, CodingKey {
            case specification, points, available, percentage
            case fractionOfAvailable = "fraction_of_available"
            case scoredRuns = "scored_runs"
            case unscoredRuns = "unscored_runs"
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(specification, forKey: .specification)
            try container.encode(points, forKey: .points)
            try container.encode(available, forKey: .available)
            try container.encode(fractionOfAvailable, forKey: .fractionOfAvailable)
            try container.encode(percentage, forKey: .percentage)
            try container.encode(scoredRuns, forKey: .scoredRuns)
            try container.encode(unscoredRuns, forKey: .unscoredRuns)
        }

        init(results: [BenchmarkRunResult], weights: [String: Int]) {
            specification = AppleBenchScore.specification
            var earned = 0
            var possible = 0
            var scored = 0
            var unscored = 0

            for result in results {
                guard let taskPoints = AppleBenchScore.points(for: result, weights: weights) else {
                    unscored += 1
                    continue
                }
                scored += 1
                possible += weights[result.task] ?? 0
                earned += taskPoints
            }

            points = earned
            available = possible
            scoredRuns = scored
            unscoredRuns = unscored
        }
    }
}
