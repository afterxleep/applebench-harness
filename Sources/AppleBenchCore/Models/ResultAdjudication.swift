import Foundation

/// A reviewable correction applied when recorded evidence proves that a
/// grader, rather than the model's workspace, produced the wrong verdict.
///
/// The original `result.json` remains immutable. Aggregation looks for this
/// sibling document and applies only the named grader overrides, preserving
/// the agent output, usage, timing, and every other measured field.
public struct ResultAdjudication: Sendable, Codable, Equatable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var sourceRunID: String
    public var reason: String
    public var evidence: [String]
    public var graders: [GraderOverride]

    public struct GraderOverride: Sendable, Codable, Equatable {
        public var index: Int
        public var name: String
        public var passed: Bool
        public var summary: String

        public init(index: Int, name: String, passed: Bool, summary: String) {
            self.index = index
            self.name = name
            self.passed = passed
            self.summary = summary
        }
    }

    public enum Error: Swift.Error, Equatable {
        case unsupportedSchema
        case sourceRunMismatch
        case graderIndexOutOfBounds
        case graderMismatch
    }

    enum CodingKeys: String, CodingKey {
        case reason, evidence, graders
        case schemaVersion = "schema_version"
        case sourceRunID = "source_run_id"
    }

    public init(
        sourceRunID: String,
        reason: String,
        evidence: [String],
        graders: [GraderOverride]
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.sourceRunID = sourceRunID
        self.reason = reason
        self.evidence = evidence
        self.graders = graders
    }

    public func applying(to original: BenchmarkRunResult) throws -> BenchmarkRunResult {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw Error.unsupportedSchema
        }
        guard sourceRunID == original.runID else {
            throw Error.sourceRunMismatch
        }

        var corrected = original
        for override in graders {
            guard corrected.graders.indices.contains(override.index) else {
                throw Error.graderIndexOutOfBounds
            }
            guard corrected.graders[override.index].name == override.name else {
                throw Error.graderMismatch
            }
            corrected.graders[override.index].passed = override.passed
            corrected.graders[override.index].summary = override.summary
        }
        corrected.result.passed = corrected.graders.allSatisfy(\.passed)
        return corrected
    }

    public func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(self).write(to: url)
    }

    public static func read(from url: URL) throws -> ResultAdjudication {
        try JSONDecoder().decode(ResultAdjudication.self, from: Data(contentsOf: url))
    }
}

public extension BenchmarkRunResult {
    /// Reads the immutable measurement plus an optional reviewed correction
    /// stored beside it as `adjudication.json`.
    static func readForAggregation(from resultURL: URL) throws -> BenchmarkRunResult {
        let original = try read(from: resultURL)
        let adjudicationURL = resultURL
            .deletingLastPathComponent()
            .appendingPathComponent("adjudication.json")
        guard FileManager.default.fileExists(atPath: adjudicationURL.path) else {
            return original
        }
        return try ResultAdjudication.read(from: adjudicationURL).applying(to: original)
    }
}
