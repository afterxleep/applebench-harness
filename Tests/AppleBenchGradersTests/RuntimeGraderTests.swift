import AppleBenchCore
import Foundation
import Testing
@testable import AppleBenchGraders

@Suite("Runtime grader")
struct RuntimeGraderTests {

    @Test("findAppBundle returns the .app under the iphonesimulator configuration")
    func findAppBundleHappyPath() async throws {
        let derived = FileManager.default.temporaryDirectory
            .appendingPathComponent("applebench-runtime-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: derived) }
        let products = derived.appendingPathComponent("Build/Products/Debug-iphonesimulator")
        try FileManager.default.createDirectory(at: products, withIntermediateDirectories: true)
        let app = products.appendingPathComponent("MyApp.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        // A stray macOS products directory must NOT be picked up.
        let macProducts = derived.appendingPathComponent("Build/Products/Debug")
        try FileManager.default.createDirectory(at: macProducts, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: macProducts.appendingPathComponent("MyApp.app"),
            withIntermediateDirectories: true
        )

        let found = try #require(RuntimeGrader.findAppBundle(in: derived))
        // Compare standardized paths so /var/folders and /private/var/folders
        // (a macOS symlink) compare equal.
        #expect(found.standardizedFileURL.path == app.standardizedFileURL.path)
    }

    @Test("findAppBundle returns nil when no simulator products exist")
    func findAppBundleMissing() throws {
        let derived = FileManager.default.temporaryDirectory
            .appendingPathComponent("applebench-runtime-missing-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: derived) }
        let products = derived.appendingPathComponent("Build/Products/Debug")
        try FileManager.default.createDirectory(at: products, withIntermediateDirectories: true)
        // No .app under products.
        #expect(RuntimeGrader.findAppBundle(in: derived) == nil)
    }

    @Test("findAppBundle returns nil when Build/Products is absent")
    func findAppBundleNoProducts() throws {
        let derived = FileManager.default.temporaryDirectory
            .appendingPathComponent("applebench-runtime-empty-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: derived) }
        #expect(RuntimeGrader.findAppBundle(in: derived) == nil)
    }

    @Test("Runtime grader rejects a missing simulator UDID as an infrastructure failure")
    func missingSimulator() async throws {
        let runner = FakeProcessRunner()
        let (context, _) = try await makeGradingContext(processRunner: runner)
        // simulatorUDID is nil by default in makeGradingContext.

        let grader = RuntimeGrader(configuration: RuntimeGraderConfiguration(
            scheme: "App",
            launch: RuntimeLaunchConfiguration(bundleIdentifier: "com.example.app"),
            observationSeconds: 1
        ))
        await #expect(throws: BenchmarkFailure.self) {
            _ = try await grader.grade(task: defaultTask(), context: context)
        }
    }

    @Test("Runtime grader rejects a missing scheme as an invalid task")
    func missingScheme() async throws {
        let runner = FakeProcessRunner()
        let (context, workspace) = try await makeGradingContext(processRunner: runner)
        defer { try? FileManager.default.removeItem(at: workspace) }
        // Manufacture a context with a non-nil simulatorUDID by hand.
        let simContext = GradingContext(
            runID: "test",
            workspaceURL: context.workspaceURL,
            runDirectoryURL: context.runDirectoryURL,
            artifactsDirectoryURL: context.artifactsDirectoryURL,
            derivedDataURL: context.derivedDataURL,
            simulatorUDID: "FAKE-UDID",
            destination: context.destination,
            changedFiles: context.changedFiles,
            processRunner: context.processRunner,
            recorder: context.recorder
        )

        let grader = RuntimeGrader(configuration: RuntimeGraderConfiguration(
            // No scheme supplied.
            launch: RuntimeLaunchConfiguration(bundleIdentifier: "com.example.app"),
            observationSeconds: 1
        ))
        await #expect(throws: BenchmarkFailure.self) {
            _ = try await grader.grade(task: defaultTask(), context: simContext)
        }
    }

    @Test("A build failure short-circuits to FAIL with the build log as evidence")
    func buildFailure() async throws {
        let runner = FakeProcessRunner()
        runner.enqueue(exitCode: 65, standardError: "error: cannot find 'X'\n")
        let (context, workspace) = try await makeGradingContext(processRunner: runner)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let simContext = GradingContext(
            runID: "test",
            workspaceURL: context.workspaceURL,
            runDirectoryURL: context.runDirectoryURL,
            artifactsDirectoryURL: context.artifactsDirectoryURL,
            derivedDataURL: context.derivedDataURL,
            simulatorUDID: "FAKE-UDID",
            destination: context.destination,
            changedFiles: context.changedFiles,
            processRunner: context.processRunner,
            recorder: context.recorder
        )

        let grader = RuntimeGrader(configuration: RuntimeGraderConfiguration(
            scheme: "App",
            launch: RuntimeLaunchConfiguration(bundleIdentifier: "com.example.app"),
            observationSeconds: 1
        ))
        let result = try await grader.grade(task: defaultTask(), context: simContext)
        #expect(!result.passed)
        #expect(result.summary.contains("build"))
        #expect(result.evidence.contains { $0.name == "runtime-build.log" })
    }
}
