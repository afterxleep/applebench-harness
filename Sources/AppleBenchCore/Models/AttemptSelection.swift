import Foundation

/// Which attempt counts when a task was run more than once.
///
/// Tasks get re-run — a simulator wedges, a model id is mistyped, a harness bug
/// is fixed — and a directory of runs then holds several attempts at the same
/// task. "First", "latest" and "best" produce materially different headlines
/// from exactly the same data, and a reader cannot infer which was used, so the
/// rule is chosen explicitly at export time and recorded in the export.
///
/// Selection is keyed on the task *and* the configuration that ran it. Keying
/// on the task alone would let one model's run supersede another's and quietly
/// drop it from the export.
public enum AttemptSelection: String, Sendable, CaseIterable {
    /// No selection: every run counts, and a re-run task carries more weight.
    case all
    /// The earliest attempt, by run id.
    case first
    /// The most recent attempt, by run id.
    case latest
    /// The earliest passing attempt, or the earliest attempt when none passed.
    case best

    public func apply(to results: [BenchmarkRunResult]) -> [BenchmarkRunResult] {
        guard self != .all else { return results }

        let grouped = Dictionary(grouping: results) { result in
            Key(task: result.task, configuration: Self.configurationLabel(of: result))
        }
        return grouped.values.compactMap { attempts in
            // Run ids begin with a UTC timestamp, so sorting them orders the
            // attempts. Sorting first also makes every rule deterministic
            // regardless of the order the enumerator returned them in.
            let ordered = attempts.sorted { $0.runID < $1.runID }
            switch self {
            case .all: return nil
            case .first: return ordered.first
            case .latest: return ordered.last
            case .best: return ordered.first { $0.result.passed } ?? ordered.first
            }
        }
        .sorted { $0.runID < $1.runID }
    }

    static func configurationLabel(of result: BenchmarkRunResult) -> String {
        result.agent.model.map { "\(result.agent.agent) · \($0)" } ?? result.agent.agent
    }

    private struct Key: Hashable {
        var task: String
        var configuration: String
    }
}
