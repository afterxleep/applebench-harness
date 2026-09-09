import Foundation

/// Combines an immutable published baseline with newer run artifacts.
///
/// Long benchmark matrices may archive old workspaces after publishing. A
/// targeted calibration should not require rerunning those unaffected tasks,
/// so publication can use the previous report as its baseline and replace
/// only run ids for which a live artifact exists.
public enum ResultCollection {
    public static func merged(
        baseReports: [URL],
        live: [BenchmarkRunResult]
    ) throws -> [BenchmarkRunResult] {
        var byRunID: [String: BenchmarkRunResult] = [:]
        for url in baseReports {
            let report = try JSONDecoder().decode(
                Report.self,
                from: Data(contentsOf: url)
            )
            for result in report.runs {
                byRunID[result.runID] = result
            }
        }
        for result in live {
            byRunID[result.runID] = result
        }
        return byRunID.values.sorted { $0.runID < $1.runID }
    }

    private struct Report: Decodable {
        var runs: [BenchmarkRunResult]
    }
}
