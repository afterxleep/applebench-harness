import Foundation
import Testing
@testable import AppleBenchCore
@testable import AppleBenchGraders

@Suite("File grader")
struct FileGraderTests {
    private func makeContext(changedFiles: [String] = []) throws -> (GradingContext, URL) {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("applebench-filegrader-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let context = GradingContext(
            runID: "test",
            workspaceURL: workspace,
            runDirectoryURL: workspace,
            artifactsDirectoryURL: workspace,
            derivedDataURL: workspace.appendingPathComponent("DerivedData"),
            simulatorUDID: nil,
            destination: nil,
            changedFiles: changedFiles,
            processRunner: ProcessRunner(),
            recorder: try EventRecorder(runID: "test", fileURL: nil)
        )
        return (context, workspace)
    }

    private var task: BenchmarkTask {
        BenchmarkTask(
            id: "t",
            title: "t",
            repository: RepositorySpecification(url: "/tmp", commit: "HEAD"),
            prompt: "p",
            environment: EnvironmentRequirements(platform: .ios)
        )
    }

    @Test("contains, matches, and exists assertions")
    func assertions() async throws {
        let (context, workspace) = try makeContext()
        defer { try? FileManager.default.removeItem(at: workspace) }
        try "struct Configuration { let retries = 3 }\n".write(
            to: workspace.appendingPathComponent("Configuration.swift"),
            atomically: true, encoding: .utf8
        )

        let passing = FileGrader(configuration: FileGraderConfiguration(assertions: [
            FileAssertion(path: "Configuration.swift", exists: true, contains: "retries"),
            FileAssertion(path: "Configuration.swift", matches: #"retries\s*=\s*\d+"#),
            FileAssertion(path: "Missing.swift", exists: false),
        ]))
        let result = try await passing.grade(task: task, context: context)
        #expect(result.passed)

        let failing = FileGrader(configuration: FileGraderConfiguration(assertions: [
            FileAssertion(path: "Configuration.swift", contains: "not-there"),
        ]))
        let failure = try await failing.grade(task: task, context: context)
        #expect(!failure.passed)
        #expect(failure.summary.contains("Configuration.swift"))
    }

    @Test("changed assertions consult the run diff")
    func changedAssertions() async throws {
        let (context, workspace) = try makeContext(changedFiles: ["App/Feature.swift"])
        defer { try? FileManager.default.removeItem(at: workspace) }

        let grader = FileGrader(configuration: FileGraderConfiguration(assertions: [
            FileAssertion(path: "App/Feature.swift", changed: true),
            FileAssertion(path: "App/Untouchable.swift", changed: false),
        ]))
        let result = try await grader.grade(task: task, context: context)
        #expect(result.passed)

        let wrong = FileGrader(configuration: FileGraderConfiguration(assertions: [
            FileAssertion(path: "App/Untouchable.swift", changed: true),
        ]))
        let failure = try await wrong.grade(task: task, context: context)
        #expect(!failure.passed)
    }

    @Test("Paths escaping the workspace are rejected as invalid tasks")
    func pathEscape() async throws {
        let (context, workspace) = try makeContext()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let grader = FileGrader(configuration: FileGraderConfiguration(assertions: [
            FileAssertion(path: "../../etc/passwd", exists: true),
        ]))
        await #expect(throws: BenchmarkFailure.self) {
            _ = try await grader.grade(task: task, context: context)
        }
    }

    @Test("Sibling directories that share the workspace prefix are not inside it")
    func siblingDirectoryPrefix() async throws {
        // `/tmp/applebench-filegrader-<UUID>` is the workspace. A path that
        // appends "-evil" to the workspace directory name must NOT be
        // admitted by hasPrefix checks: only an exact match or a path
        // joined by `/` lives inside the workspace.
        let (context, workspace) = try makeContext()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let sibling = workspace.deletingLastPathComponent()
            .appendingPathComponent(workspace.lastPathComponent + "-evil")
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sibling) }
        try "x".write(
            to: sibling.appendingPathComponent("exfiltrated.swift"),
            atomically: true, encoding: .utf8
        )

        let grader = FileGrader(configuration: FileGraderConfiguration(assertions: [
            FileAssertion(path: "../\(workspace.lastPathComponent)-evil/exfiltrated.swift", exists: true),
        ]))
        await #expect(throws: BenchmarkFailure.self) {
            _ = try await grader.grade(task: task, context: context)
        }
    }

    @Test("Invalid regex is an invalid task, not a FAIL")
    func invalidRegex() async throws {
        let (context, workspace) = try makeContext()
        defer { try? FileManager.default.removeItem(at: workspace) }
        try "x".write(to: workspace.appendingPathComponent("a.swift"), atomically: true, encoding: .utf8)

        let grader = FileGrader(configuration: FileGraderConfiguration(assertions: [
            FileAssertion(path: "a.swift", matches: "([unclosed"),
        ]))
        await #expect(throws: BenchmarkFailure.self) {
            _ = try await grader.grade(task: task, context: context)
        }
    }

    @Test("min_size catches stub deliverables without dictating content")
    func minSize() async throws {
        let (context, workspace) = try makeContext()
        defer { try? FileManager.default.removeItem(at: workspace) }
        // 50 bytes of report
        try String(repeating: "x", count: 50).write(
            to: workspace.appendingPathComponent("report.md"),
            atomically: true, encoding: .utf8
        )

        // min_size below actual size passes
        let passing = FileGrader(configuration: FileGraderConfiguration(assertions: [
            FileAssertion(path: "report.md", minSize: 10),
        ]))
        #expect(try await passing.grade(task: task, context: context).passed)

        // min_size above actual size fails — catches the stub
        let failing = FileGrader(configuration: FileGraderConfiguration(assertions: [
            FileAssertion(path: "report.md", minSize: 200),
        ]))
        let result = try await failing.grade(task: task, context: context)
        #expect(!result.passed)
        #expect(result.summary.contains("bytes"))
    }

    @Test("is_json verifies the file is a real JSON dump, not a renamed text file")
    func isJSON() async throws {
        let (context, workspace) = try makeContext()
        defer { try? FileManager.default.removeItem(at: workspace) }
        try #"{"action":"build","target":"ConcurrencyFixture"}"#.write(
            to: workspace.appendingPathComponent("build-settings.json"),
            atomically: true, encoding: .utf8
        )
        try "this is not json at all".write(
            to: workspace.appendingPathComponent("not-json.txt"),
            atomically: true, encoding: .utf8
        )

        // valid JSON passes
        let passing = FileGrader(configuration: FileGraderConfiguration(assertions: [
            FileAssertion(path: "build-settings.json", isJSON: true),
        ]))
        #expect(try await passing.grade(task: task, context: context).passed)

        // non-JSON fails
        let failing = FileGrader(configuration: FileGraderConfiguration(assertions: [
            FileAssertion(path: "not-json.txt", isJSON: true),
        ]))
        let result = try await failing.grade(task: task, context: context)
        #expect(!result.passed)
        #expect(result.summary.contains("not valid JSON"))
    }

    @Test("glob finds the artifact anywhere in the workspace, not just at a fixed path")
    func glob() async throws {
        let (context, workspace) = try makeContext()
        defer { try? FileManager.default.removeItem(at: workspace) }

        // Agent put the archive under build/ instead of the workspace root.
        // The grader's glob should still find it.
        let archiveInfo = workspace
            .appendingPathComponent("build")
            .appendingPathComponent("Fixture.xcarchive")
            .appendingPathComponent("Info.plist")
        try FileManager.default.createDirectory(
            at: archiveInfo.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "<plist/>".write(to: archiveInfo, atomically: true, encoding: .utf8)

        // ** matches zero or more directory levels
        let passing = FileGrader(configuration: FileGraderConfiguration(assertions: [
            FileAssertion(path: "**/Fixture.xcarchive/Info.plist", exists: true, glob: true),
        ]))
        #expect(try await passing.grade(task: task, context: context).passed)

        // A glob that finds nothing fails
        let missing = FileGrader(configuration: FileGraderConfiguration(assertions: [
            FileAssertion(path: "**/NoSuchArtifact.txt", exists: true, glob: true),
        ]))
        let result = try await missing.grade(task: task, context: context)
        #expect(!result.passed)
        #expect(result.summary.contains("no workspace file matched"))
    }
}
