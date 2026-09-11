import Foundation
import Testing
@testable import AppleBenchCore

@Suite("Withheld verification lifecycle", .serialized)
struct VerificationMaterialiserTests {
    @Test("Sealed verification fetches have a five-attempt default budget")
    func hasThoroughDefaultRetryBudget() {
        #expect(VerificationMaterialiser.defaultFetchAttemptCount == 5)
    }

    @Test("Tests are fetched from the sealed repository only when grading begins")
    func fetchesAfterAgentExit() async throws {
        let sealedRepository = FileManager.default.temporaryDirectory
            .appendingPathComponent("applebench-sealed-verification-\(UUID().uuidString)", isDirectory: true)
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("applebench-verification-workspace-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: sealedRepository)
            try? FileManager.default.removeItem(at: workspace)
        }

        let tests = sealedRepository
            .appendingPathComponent("Fixtures/SecretFixture/Tests", isDirectory: true)
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
        try "hidden assertion\n".write(
            to: tests.appendingPathComponent("HiddenTests.swift"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)

        let runner = ProcessRunner()
        for arguments in [["init", "-q"], ["add", "-A"], ["commit", "-qm", "sealed tests"]] {
            let result = try await runner.run(ProcessCommand(
                executable: "/usr/bin/git",
                arguments: arguments,
                workingDirectory: sealedRepository,
                environment: [
                    "PATH": "/usr/bin:/bin",
                    "GIT_AUTHOR_NAME": "T", "GIT_AUTHOR_EMAIL": "t@t",
                    "GIT_COMMITTER_NAME": "T", "GIT_COMMITTER_EMAIL": "t@t",
                ]
            ))
            #expect(result.exitCode == 0)
        }
        let revision = try await runner.run(ProcessCommand(
            executable: "/usr/bin/git",
            arguments: ["rev-parse", "HEAD"],
            workingDirectory: sealedRepository
        )).standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)

        let hiddenTest = workspace.appendingPathComponent("Tests/HiddenTests.swift")
        #expect(!FileManager.default.fileExists(atPath: hiddenTest.path))

        let materialiser = VerificationMaterialiser(
            source: .init(
                repository: sealedRepository.path,
                revision: revision,
                fixtures: ["SecretFixture"]
            ),
            fetchRetryDelays: [.zero, .zero]
        )
        let outcome = try await materialiser.materialise(
            fixture: "SecretFixture",
            into: workspace,
            processRunner: runner
        )

        #expect(outcome.paths == ["Tests"])
        #expect(FileManager.default.fileExists(atPath: hiddenTest.path))
        #expect(try String(contentsOf: hiddenTest, encoding: .utf8) == "hidden assertion\n")
    }

    @Test("A transient sealed repository fetch failure is retried")
    func retriesTransientFetchFailure() async throws {
        let sealedRepository = FileManager.default.temporaryDirectory
            .appendingPathComponent("applebench-sealed-verification-\(UUID().uuidString)", isDirectory: true)
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("applebench-verification-workspace-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: sealedRepository)
            try? FileManager.default.removeItem(at: workspace)
        }

        let tests = sealedRepository
            .appendingPathComponent("Fixtures/SecretFixture/Tests", isDirectory: true)
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
        try "hidden assertion\n".write(
            to: tests.appendingPathComponent("HiddenTests.swift"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)

        let setupRunner = ProcessRunner()
        for arguments in [["init", "-q"], ["add", "-A"], ["commit", "-qm", "sealed tests"]] {
            let result = try await setupRunner.run(ProcessCommand(
                executable: "/usr/bin/git",
                arguments: arguments,
                workingDirectory: sealedRepository,
                environment: [
                    "PATH": "/usr/bin:/bin",
                    "GIT_AUTHOR_NAME": "T", "GIT_AUTHOR_EMAIL": "t@t",
                    "GIT_COMMITTER_NAME": "T", "GIT_COMMITTER_EMAIL": "t@t",
                ]
            ))
            #expect(result.exitCode == 0)
        }
        let revision = try await setupRunner.run(ProcessCommand(
            executable: "/usr/bin/git",
            arguments: ["rev-parse", "HEAD"],
            workingDirectory: sealedRepository
        )).standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)

        let runner = TransientFetchProcessRunner()
        let materialiser = VerificationMaterialiser(
            source: .init(
                repository: sealedRepository.path,
                revision: revision,
                fixtures: ["SecretFixture"]
            ),
            fetchRetryDelays: [.zero, .zero]
        )
        let outcome = try await materialiser.materialise(
            fixture: "SecretFixture",
            into: workspace,
            processRunner: runner
        )

        #expect(outcome.paths == ["Tests"])
        #expect(await runner.fetchAttempts == 2)
        #expect(await runner.verifiedFetchHead)
    }

    @Test("A failed sealed fetch reports actionable diagnostics without credentials")
    func reportsSafeFetchDiagnostics() async throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("applebench-verification-workspace-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)

        let materialiser = VerificationMaterialiser(
            source: .init(
                repository: "https://secret-token@example.com/sealed.git",
                revision: "deadbeef",
                fixtures: ["SecretFixture"]
            ),
            fetchRetryDelays: [.zero, .zero]
        )

        do {
            _ = try await materialiser.materialise(
                fixture: "SecretFixture",
                into: workspace,
                processRunner: FailedFetchProcessRunner()
            )
            Issue.record("Expected the sealed fetch to fail")
        } catch {
            let message = String(describing: error)
            #expect(message.contains("fetch"))
            #expect(message.contains("exit code 128"))
            #expect(message.contains("repository access failed"))
            #expect(!message.contains("secret-token"))
        }
    }

    @Test("A failed sealed fetch reports every attempt, including silent timeouts")
    func reportsAllFetchAttempts() async throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("applebench-verification-workspace-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)

        let materialiser = VerificationMaterialiser(
            source: .init(
                repository: "https://example.com/sealed.git",
                revision: "deadbeef",
                fixtures: ["SecretFixture"]
            ),
            fetchRetryDelays: [.zero, .zero]
        )

        do {
            _ = try await materialiser.materialise(
                fixture: "SecretFixture",
                into: workspace,
                processRunner: SilentTimeoutFetchProcessRunner()
            )
            Issue.record("Expected the sealed fetch to fail")
        } catch {
            let message = String(describing: error)
            #expect(message.contains("attempt 1 of 3: exit code 128: remote closed the connection"))
            #expect(message.contains("attempt 2 of 3: timed out: Git produced no diagnostic output."))
            #expect(message.contains("attempt 3 of 3: exit code 128: final network failure"))
        }
    }

    @Test("A fetched sealed revision is checked before verification files are copied")
    func rejectsMismatchedFetchedRevision() async throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("applebench-verification-workspace-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)

        let materialiser = VerificationMaterialiser(
            source: .init(
                repository: "https://example.com/sealed.git",
                revision: "deadbeef",
                fixtures: ["SecretFixture"]
            ),
            fetchRetryDelays: []
        )

        do {
            _ = try await materialiser.materialise(
                fixture: "SecretFixture",
                into: workspace,
                processRunner: MismatchedRevisionProcessRunner()
            )
            Issue.record("Expected the mismatched revision to fail")
        } catch {
            let message = String(describing: error)
            #expect(message.contains("cafebabe"))
            #expect(message.contains("deadbeef"))
            #expect(message.contains("SecretFixture"))
        }
    }
}

private actor TransientFetchProcessRunner: ProcessRunning {
    private let runner = ProcessRunner()
    private(set) var fetchAttempts = 0
    private(set) var verifiedFetchHead = false

    func run(
        _ command: ProcessCommand,
        timeout: Duration?,
        outputHandler: (@Sendable (ProcessOutputStream, String) -> Void)?
    ) async throws -> ProcessExecutionResult {
        if command.arguments.first == "fetch" {
            fetchAttempts += 1
            if fetchAttempts == 1 {
                return ProcessExecutionResult(
                    exitCode: 1,
                    standardOutput: "",
                    standardError: "transient fetch failure",
                    duration: .zero,
                    timedOut: false
                )
            }
        }
        if command.arguments.starts(with: ["rev-parse", "--verify", "FETCH_HEAD^{commit}"]) {
            verifiedFetchHead = true
        }
        return try await runner.run(command, timeout: timeout, outputHandler: outputHandler)
    }
}

private actor FailedFetchProcessRunner: ProcessRunning {
    func run(
        _ command: ProcessCommand,
        timeout: Duration?,
        outputHandler: (@Sendable (ProcessOutputStream, String) -> Void)?
    ) async throws -> ProcessExecutionResult {
        switch command.arguments.first {
        case "init", "remote":
            return ProcessExecutionResult(
                exitCode: 0,
                standardOutput: "",
                standardError: "",
                duration: .zero,
                timedOut: false
            )
        case "fetch":
            return ProcessExecutionResult(
                exitCode: 128,
                standardOutput: "fatal: repository access failed for https://secret-token@example.com/sealed.git",
                standardError: "",
                duration: .zero,
                timedOut: false
            )
        default:
            Issue.record("Unexpected command: \(command.displayString)")
            return ProcessExecutionResult(
                exitCode: 1,
                standardOutput: "",
                standardError: "",
                duration: .zero,
                timedOut: false
            )
        }
    }
}

private actor SilentTimeoutFetchProcessRunner: ProcessRunning {
    private var fetchAttempts = 0

    func run(
        _ command: ProcessCommand,
        timeout: Duration?,
        outputHandler: (@Sendable (ProcessOutputStream, String) -> Void)?
    ) async throws -> ProcessExecutionResult {
        switch command.arguments.first {
        case "init", "remote":
            return ProcessExecutionResult(
                exitCode: 0,
                standardOutput: "",
                standardError: "",
                duration: .zero,
                timedOut: false
            )
        case "fetch":
            fetchAttempts += 1
            switch fetchAttempts {
            case 1:
                return ProcessExecutionResult(
                    exitCode: 128,
                    standardOutput: "",
                    standardError: "remote closed the connection",
                    duration: .seconds(1),
                    timedOut: false
                )
            case 2:
                return ProcessExecutionResult(
                    terminationSignal: 15,
                    standardOutput: "",
                    standardError: "",
                    duration: .seconds(300),
                    timedOut: true
                )
            default:
                return ProcessExecutionResult(
                    exitCode: 128,
                    standardOutput: "",
                    standardError: "final network failure",
                    duration: .seconds(1),
                    timedOut: false
                )
            }
        default:
            Issue.record("Unexpected command: \(command.displayString)")
            return ProcessExecutionResult(
                exitCode: 1,
                standardOutput: "",
                standardError: "",
                duration: .zero,
                timedOut: false
            )
        }
    }
}

private actor MismatchedRevisionProcessRunner: ProcessRunning {
    func run(
        _ command: ProcessCommand,
        timeout: Duration?,
        outputHandler: (@Sendable (ProcessOutputStream, String) -> Void)?
    ) async throws -> ProcessExecutionResult {
        let output: String
        switch command.arguments.first {
        case "init", "remote", "fetch":
            output = ""
        case "rev-parse":
            output = "cafebabe\n"
        default:
            Issue.record("Unexpected command: \(command.displayString)")
            return ProcessExecutionResult(
                exitCode: 1,
                standardOutput: "",
                standardError: "",
                duration: .zero,
                timedOut: false
            )
        }
        return ProcessExecutionResult(
            exitCode: 0,
            standardOutput: output,
            standardError: "",
            duration: .zero,
            timedOut: false
        )
    }
}
