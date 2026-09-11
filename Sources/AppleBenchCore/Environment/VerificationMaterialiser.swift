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
    private let fetchRetryDelays: [Duration]

    public init(source: Source? = nil) {
        self.source = source
        self.fetchRetryDelays = [.seconds(1), .seconds(2)]
    }

    init(source: Source?, fetchRetryDelays: [Duration]) {
        self.source = source
        self.fetchRetryDelays = fetchRetryDelays
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

        try await runGit(
            ["init", "--quiet"],
            stage: "initialise the verification checkout",
            in: checkout,
            using: processRunner,
            fixture: fixture,
            source: source
        )
        try await runGit(
            ["remote", "add", "origin", source.repository],
            stage: "configure the sealed repository",
            in: checkout,
            using: processRunner,
            fixture: fixture,
            source: source
        )
        try await fetchVerification(
            source: source,
            in: checkout,
            using: processRunner,
            fixture: fixture
        )
        try await runGit(
            ["checkout", "--quiet", "FETCH_HEAD", "--", "Fixtures/\(fixture)"],
            stage: "check out the verification fixture",
            in: checkout,
            using: processRunner,
            fixture: fixture,
            source: source
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
        stage: String,
        in directory: URL,
        using processRunner: any ProcessRunning,
        fixture: String,
        source: Source
    ) async throws {
        let result = try await executeGit(arguments, in: directory, using: processRunner)
        guard result.succeeded else {
            throw gitFailure(stage: stage, result: result, fixture: fixture, source: source)
        }
    }

    private func fetchVerification(
        source: Source,
        in directory: URL,
        using processRunner: any ProcessRunning,
        fixture: String
    ) async throws {
        for attempt in 0...fetchRetryDelays.count {
            var arguments = ["fetch", "--depth=1"]
            if attempt == 0 {
                arguments.append("--filter=blob:none")
            }
            arguments.append(contentsOf: ["origin", source.revision])

            let result = try await executeGit(arguments, in: directory, using: processRunner)
            if result.succeeded { return }
            guard attempt < fetchRetryDelays.count else {
                throw gitFailure(
                    stage: "fetch the sealed verification after \(attempt + 1) attempts",
                    result: result,
                    fixture: fixture,
                    source: source
                )
            }
            try await Task.sleep(for: fetchRetryDelays[attempt])
        }
    }

    private func executeGit(
        _ arguments: [String],
        in directory: URL,
        using processRunner: any ProcessRunning
    ) async throws -> ProcessExecutionResult {
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        return try await processRunner.run(
            ProcessCommand(
                executable: "/usr/bin/git",
                arguments: arguments,
                workingDirectory: directory,
                environment: environment
            ),
            timeout: .seconds(300)
        )
    }

    private func gitFailure(
        stage: String,
        result: ProcessExecutionResult,
        fixture: String,
        source: Source
    ) -> BenchmarkFailure {
        let termination: String
        if result.timedOut {
            termination = "timed out"
        } else if let exitCode = result.exitCode {
            termination = "exit code \(exitCode)"
        } else if let signal = result.terminationSignal {
            termination = "signal \(signal)"
        } else {
            termination = "unknown termination"
        }

        let combinedOutput = [result.standardError, result.standardOutput]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        let diagnostic = combinedOutput.isEmpty
            ? "Git produced no diagnostic output."
            : Self.redactedDiagnostic(combinedOutput, repository: source.repository)

        return BenchmarkFailure.graderFailure(
            grader: "verification",
            message: "Could not \(stage) for \(fixture) (\(termination)). \(diagnostic)"
        )
    }

    private static func redactedDiagnostic(_ diagnostic: String, repository: String) -> String {
        let withoutRepository = diagnostic.replacingOccurrences(
            of: repository,
            with: "[sealed repository]"
        )
        let pattern = #"(?i)(https?://)[^/@\s]+@"#
        let range = NSRange(withoutRepository.startIndex..., in: withoutRepository)
        let redacted = (try? NSRegularExpression(pattern: pattern))?.stringByReplacingMatches(
            in: withoutRepository,
            range: range,
            withTemplate: "$1[redacted]@"
        ) ?? withoutRepository
        return String(redacted.prefix(2_000))
    }

    public static func fixtureName(for task: BenchmarkTask) -> String {
        var url = task.repository.url
        while url.hasSuffix("/") { url.removeLast() }
        let name = (url as NSString).lastPathComponent
        return name.hasSuffix(".git") ? String(name.dropLast(4)) : name
    }
}
