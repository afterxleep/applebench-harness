import Foundation
import Testing
@testable import AppleBenchCore

@Suite("Workspace lifecycle", .serialized)
struct WorkspaceManagerTests {
    private let manager = WorkspaceManager()
    private let runner = ProcessRunner()

    /// Creates a local git repository with two commits and returns
    /// (path, firstSHA, secondSHA).
    private func makeSourceRepository() async throws -> (URL, String, String) {
        let repoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("applebench-src-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)

        func git(_ arguments: [String]) async throws -> String {
            let result = try await runner.run(
                ProcessCommand(
                    executable: "/usr/bin/git",
                    arguments: arguments,
                    workingDirectory: repoURL,
                    environment: [
                        "PATH": "/usr/bin:/bin",
                        "GIT_AUTHOR_NAME": "Test", "GIT_AUTHOR_EMAIL": "t@t",
                        "GIT_COMMITTER_NAME": "Test", "GIT_COMMITTER_EMAIL": "t@t",
                    ]
                )
            )
            #expect(result.exitCode == 0, "git \(arguments) failed: \(result.standardError)")
            return result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        _ = try await git(["init", "-q"])
        try "let version = 1\n".write(to: repoURL.appendingPathComponent("App.swift"), atomically: true, encoding: .utf8)
        _ = try await git(["add", "-A"])
        _ = try await git(["commit", "-qm", "first"])
        let first = try await git(["rev-parse", "HEAD"])

        try "let version = 2\n".write(to: repoURL.appendingPathComponent("App.swift"), atomically: true, encoding: .utf8)
        _ = try await git(["add", "-A"])
        _ = try await git(["commit", "-qm", "second"])
        let second = try await git(["rev-parse", "HEAD"])

        return (repoURL, first, second)
    }

    private func makeRunDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("applebench-run-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Clones and checks out the exact commit")
    func exactCommit() async throws {
        let (repoURL, first, second) = try await makeSourceRepository()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        let runDirectory = try makeRunDirectory()
        defer { try? FileManager.default.removeItem(at: runDirectory) }

        let workspace = try await manager.prepareWorkspace(
            repository: RepositorySpecification(url: repoURL.path, commit: first),
            runDirectoryURL: runDirectory
        )
        #expect(workspace.baseCommit == first)
        #expect(workspace.baseCommit != second)
        let contents = try String(
            contentsOf: workspace.workspaceURL.appendingPathComponent("App.swift"),
            encoding: .utf8
        )
        #expect(contents == "let version = 1\n")
    }

    @Test("HEAD checkout uses the latest commit")
    func headCheckout() async throws {
        let (repoURL, _, second) = try await makeSourceRepository()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        let runDirectory = try makeRunDirectory()
        defer { try? FileManager.default.removeItem(at: runDirectory) }

        let workspace = try await manager.prepareWorkspace(
            repository: RepositorySpecification(url: repoURL.path, commit: "HEAD"),
            runDirectoryURL: runDirectory
        )
        #expect(workspace.baseCommit == second)
    }

    @Test("Unknown commits fail as repository failures")
    func unknownCommit() async throws {
        let (repoURL, _, _) = try await makeSourceRepository()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        let runDirectory = try makeRunDirectory()
        defer { try? FileManager.default.removeItem(at: runDirectory) }

        await #expect(throws: BenchmarkFailure.self) {
            _ = try await manager.prepareWorkspace(
                repository: RepositorySpecification(url: repoURL.path, commit: "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"),
                runDirectoryURL: runDirectory
            )
        }
    }

    @Test("Diff capture reports modifications and untracked files")
    func diffCapture() async throws {
        let (repoURL, _, _) = try await makeSourceRepository()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        let runDirectory = try makeRunDirectory()
        defer { try? FileManager.default.removeItem(at: runDirectory) }

        let workspace = try await manager.prepareWorkspace(
            repository: RepositorySpecification(url: repoURL.path, commit: "HEAD"),
            runDirectoryURL: runDirectory
        )

        // Simulate agent edits: modify one file, create another.
        try "let version = 3\n".write(
            to: workspace.workspaceURL.appendingPathComponent("App.swift"),
            atomically: true, encoding: .utf8
        )
        try "struct New {}\n".write(
            to: workspace.workspaceURL.appendingPathComponent("New.swift"),
            atomically: true, encoding: .utf8
        )

        let diff = try await manager.captureDiff(workspace: workspace, runDirectoryURL: runDirectory)
        #expect(diff.filesChanged == 2)
        #expect(diff.changedFiles.sorted() == ["App.swift", "New.swift"])
        #expect(diff.insertions == 2)
        #expect(diff.deletions == 1)
        #expect(diff.finalCommit == nil)
        #expect(diff.patch.contains("New.swift"))

        let patchOnDisk = try String(
            contentsOf: runDirectory.appendingPathComponent("diff.patch"),
            encoding: .utf8
        )
        #expect(patchOnDisk == diff.patch)
    }

    @Test("No changes produce an empty diff")
    func emptyDiff() async throws {
        let (repoURL, _, _) = try await makeSourceRepository()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        let runDirectory = try makeRunDirectory()
        defer { try? FileManager.default.removeItem(at: runDirectory) }

        let workspace = try await manager.prepareWorkspace(
            repository: RepositorySpecification(url: repoURL.path, commit: "HEAD"),
            runDirectoryURL: runDirectory
        )
        let diff = try await manager.captureDiff(workspace: workspace, runDirectoryURL: runDirectory)
        #expect(diff.filesChanged == 0)
        #expect(diff.patch.isEmpty)
    }

    @Test("Run directory layout confines and sanitizes components")
    func runDirectoryLayout() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("applebench-root-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let layout = RunDirectoryLayout(rootURL: root)
        let (runID, url) = try layout.createRunDirectory(
            taskID: "nav-001",
            agentID: "weird/agent name",
            date: Date(timeIntervalSince1970: 1_754_650_000)
        )
        #expect(runID.contains("nav-001"))
        #expect(!runID.contains("/"))
        #expect(!runID.contains(" "))
        #expect(url.path.hasPrefix(root.path))
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(
            atPath: url.appendingPathComponent("logs").path,
            isDirectory: &isDirectory
        ))
        #expect(isDirectory.boolValue)
    }
}
