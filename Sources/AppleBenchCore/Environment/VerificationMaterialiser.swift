import Foundation

/// Fetches a fixture's graded tests only after the agent process has exited.
///
/// Scoring runs point this at the sealed task repository and an exact commit.
/// No verification checkout or test bundle exists in the harness while the
/// agent is running. At grading time, the selected fixture is fetched into a
/// unique temporary directory, only its project specification and test suites
/// are copied into the workspace, and the temporary checkout is removed.
public struct VerificationMaterialiser: Sendable {
    public struct Source: Sendable, Equatable {
        public var repository: String
        public var revision: String
        public var fixtures: Set<String>

        public init(repository: String, revision: String, fixtures: Set<String>) {
            self.repository = repository
            self.revision = revision
            self.fixtures = fixtures
        }
    }

    private let source: Source?

    public init(source: Source? = nil) {
        self.source = source
    }

    public struct Outcome: Sendable, Equatable {
        public var fixture: String
        public var paths: [String]

        public var isEmpty: Bool { paths.isEmpty }
    }

    @discardableResult
    public func materialise(
        fixture: String,
        into workspaceURL: URL,
        processRunner: any ProcessRunning
    ) async throws -> Outcome {
        guard let source, source.fixtures.contains(fixture) else {
            return Outcome(fixture: fixture, paths: [])
        }
        guard !fixture.isEmpty, fixture != ".", fixture != "..", !fixture.contains("/") else {
            throw BenchmarkFailure.graderFailure(
                grader: "verification",
                message: "Refusing unsafe verification fixture name: \(fixture)"
            )
        }

        let checkout = FileManager.default.temporaryDirectory
            .appendingPathComponent("applebench-verification-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: checkout, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: checkout) }

        try await runGit(["init", "--quiet"], in: checkout, using: processRunner, fixture: fixture)
        try await runGit(
            ["remote", "add", "origin", source.repository],
            in: checkout,
            using: processRunner,
            fixture: fixture
        )
        try await runGit(
            ["fetch", "--quiet", "--depth=1", "--filter=blob:none", "origin", source.revision],
            in: checkout,
            using: processRunner,
            fixture: fixture
        )
        try await runGit(
            ["checkout", "--quiet", "FETCH_HEAD", "--", "Fixtures/\(fixture)"],
            in: checkout,
            using: processRunner,
            fixture: fixture
        )

        let fetchedFixture = checkout.appendingPathComponent("Fixtures/\(fixture)", isDirectory: true)
        let allowedEntries = ["project.yml", "Tests", "UITests"]
        var written: [String] = []
        for name in allowedEntries {
            let entry = fetchedFixture.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: entry.path) else { continue }
            let destination = workspaceURL.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: entry, to: destination)
            written.append(name)
        }

        guard written.contains("Tests") || written.contains("UITests") else {
            throw BenchmarkFailure.graderFailure(
                grader: "verification",
                message: "The sealed repository has no tests for isolated fixture \(fixture) at \(source.revision)."
            )
        }

        let spec = workspaceURL.appendingPathComponent("project.yml")
        if FileManager.default.fileExists(atPath: spec.path) {
            let result = try await processRunner.run(
                ProcessCommand(
                    executable: "xcodegen",
                    arguments: ["generate", "--quiet", "--spec", "project.yml"],
                    workingDirectory: workspaceURL
                ),
                timeout: .seconds(120)
            )
            guard result.exitCode == 0 else {
                throw BenchmarkFailure.graderFailure(
                    grader: "verification",
                    message: "Could not regenerate \(fixture)'s project from its sealed spec at grading time. "
                        + "XcodeGen is required to grade an isolated fixture."
                )
            }
            try FileManager.default.removeItem(at: spec)
            written.removeAll { $0 == "project.yml" }
        }

        return Outcome(fixture: fixture, paths: written.sorted())
    }

    private func runGit(
        _ arguments: [String],
        in directory: URL,
        using processRunner: any ProcessRunning,
        fixture: String
    ) async throws {
        let result = try await processRunner.run(
            ProcessCommand(
                executable: "/usr/bin/git",
                arguments: arguments,
                workingDirectory: directory
            ),
            timeout: .seconds(300)
        )
        guard result.exitCode == 0 else {
            throw BenchmarkFailure.graderFailure(
                grader: "verification",
                message: "Could not fetch sealed verification for \(fixture): \(result.standardError)"
            )
        }
    }

    public static func fixtureName(for task: BenchmarkTask) -> String {
        var url = task.repository.url
        while url.hasSuffix("/") { url.removeLast() }
        let name = (url as NSString).lastPathComponent
        return name.hasSuffix(".git") ? String(name.dropLast(4)) : name
    }
}
