import Foundation

public struct GradingResult: Sendable, Equatable {
    public let grader: String
    public let passed: Bool
    public let duration: Duration
    public let summary: String
    public let evidence: [Artifact]

    public init(grader: String, passed: Bool, duration: Duration, summary: String, evidence: [Artifact] = []) {
        self.grader = grader
        self.passed = passed
        self.duration = duration
        self.summary = summary
        self.evidence = evidence
    }
}

/// A file produced as grading evidence (logs, xcresult bundles, screenshots),
/// referenced relative to the run directory.
public struct Artifact: Sendable, Codable, Equatable {
    public var name: String
    /// Path relative to the run directory.
    public var path: String

    public init(name: String, path: String) {
        self.name = name
        self.path = path
    }
}
