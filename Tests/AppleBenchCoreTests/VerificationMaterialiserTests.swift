import Foundation
import Testing
@testable import AppleBenchCore

@Suite("Withheld verification lifecycle", .serialized)
struct VerificationMaterialiserTests {
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

        let materialiser = VerificationMaterialiser(source: .init(
            repository: sealedRepository.path,
            revision: revision,
            fixtures: ["SecretFixture"]
        ))
        let outcome = try await materialiser.materialise(
            fixture: "SecretFixture",
            into: workspace,
            processRunner: runner
        )

        #expect(outcome.paths == ["Tests"])
        #expect(FileManager.default.fileExists(atPath: hiddenTest.path))
        #expect(try String(contentsOf: hiddenTest, encoding: .utf8) == "hidden assertion\n")
    }
}
