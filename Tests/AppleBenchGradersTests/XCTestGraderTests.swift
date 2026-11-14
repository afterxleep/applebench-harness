import AppleBenchCore
import Foundation
import Testing
@testable import AppleBenchGraders

@Suite("xcodebuild test grader")
struct XCTestGraderTests {

    /// Helper: returns the first recorded xcodebuild invocation, or nil.
    private func xcodebuildCall(_ runner: FakeProcessRunner) -> ProcessCommand? {
        runner.firstCommand { $0.executable == "/usr/bin/xcodebuild" }
    }

    @Test("A summary with zero failures and one passed test is a PASS")
    func passingSuite() async throws {
        let runner = FakeProcessRunner()
        // xcodebuild test → 0
        runner.enqueue(exitCode: 0, standardOutput: "** TEST SUCCEEDED **\n")
        // xcresulttool → summary JSON
        runner.enqueue(
            exitCode: 0,
            standardOutput: """
            {
              "result": "Succeeded",
              "totalTestCount": 1,
              "passedTests": 1,
              "failedTests": 0,
              "skippedTests": 0
            }
            """
        )
        let (context, workspace) = try await makeGradingContext(processRunner: runner)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let grader = XCTestGrader(configuration: XCTestGraderConfiguration(scheme: "App"))
        let result = try await grader.grade(task: defaultTask(), context: context)

        #expect(result.passed)
        #expect(result.grader == "xctest")
        #expect(result.summary.contains("1 executed"))
        #expect(result.summary.contains("1 passed"))
        #expect(result.summary.contains("0 failed"))
    }

    @Test("A failed test is a FAIL with the failing identifier in the summary")
    func failingTest() async throws {
        let runner = FakeProcessRunner()
        runner.enqueue(exitCode: 0)
        runner.enqueue(
            exitCode: 0,
            standardOutput: """
            {
              "result": "Failed",
              "totalTestCount": 2,
              "passedTests": 1,
              "failedTests": 1,
              "skippedTests": 0,
              "testFailures": [
                {
                  "testName": "testFoo()",
                  "testIdentifierString": "AppTests/testFoo()",
                  "failureText": "expected 1, got 2"
                }
              ]
            }
            """
        )
        let (context, workspace) = try await makeGradingContext(processRunner: runner)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let grader = XCTestGrader(configuration: XCTestGraderConfiguration(scheme: "App"))
        let result = try await grader.grade(task: defaultTask(), context: context)

        #expect(!result.passed)
        #expect(result.summary.contains("AppTests/testFoo()"))
        #expect(result.summary.contains("1 failed"))
    }

    @Test("Zero executed tests is a FAIL: a run that did not run proves nothing")
    func zeroExecuted() async throws {
        let runner = FakeProcessRunner()
        runner.enqueue(exitCode: 0)
        runner.enqueue(
            exitCode: 0,
            standardOutput: """
            {
              "result": "Succeeded",
              "totalTestCount": 0,
              "passedTests": 0,
              "failedTests": 0,
              "skippedTests": 0
            }
            """
        )
        runner.enqueue(exitCode: 0)
        runner.enqueue(
            exitCode: 0,
            standardOutput: """
            {
              "result": "Succeeded",
              "totalTestCount": 0,
              "passedTests": 0,
              "failedTests": 0,
              "skippedTests": 0
            }
            """
        )
        let (context, workspace) = try await makeGradingContext(processRunner: runner)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let grader = XCTestGrader(
            configuration: XCTestGraderConfiguration(
                scheme: "App",
                tests: ["AppTests/testPersistence"]
            )
        )
        let result = try await grader.grade(task: defaultTask(), context: context)

        #expect(!result.passed)
        #expect(result.summary.contains("No tests executed"))
    }

    @Test("A zero-test result is retried once before a verdict is recorded")
    func zeroExecutedRetriesOnce() async throws {
        let runner = FakeProcessRunner()
        runner.enqueue(exitCode: 0, standardOutput: "** TEST SUCCEEDED **\n")
        runner.enqueue(
            exitCode: 0,
            standardOutput: #"{"totalTestCount":0,"passedTests":0,"failedTests":0,"skippedTests":0}"#
        )
        runner.enqueue(exitCode: 0, standardOutput: "** TEST SUCCEEDED **\n")
        runner.enqueue(
            exitCode: 0,
            standardOutput: #"{"totalTestCount":1,"passedTests":1,"failedTests":0,"skippedTests":0}"#
        )
        let (context, workspace) = try await makeGradingContext(processRunner: runner)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let grader = XCTestGrader(
            configuration: XCTestGraderConfiguration(
                scheme: "App",
                tests: ["AppTests/testPersistence"]
            )
        )
        let result = try await grader.grade(task: defaultTask(), context: context)

        let testRuns = runner.commands().filter { $0.executable == "/usr/bin/xcodebuild" }
        #expect(testRuns.count == 2)
        #expect(result.passed)
        #expect(result.summary.contains("1 executed"))
        #expect(result.evidence.contains { $0.name == "xctest-retry.log" })
    }

    @Test("Skipped tests are excluded from the executed count")
    func skippedTests() async throws {
        let runner = FakeProcessRunner()
        runner.enqueue(exitCode: 0)
        runner.enqueue(
            exitCode: 0,
            standardOutput: """
            {
              "result": "Succeeded",
              "totalTestCount": 3,
              "passedTests": 2,
              "failedTests": 0,
              "skippedTests": 1
            }
            """
        )
        let (context, workspace) = try await makeGradingContext(processRunner: runner)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let grader = XCTestGrader(configuration: XCTestGraderConfiguration(scheme: "App"))
        let result = try await grader.grade(task: defaultTask(), context: context)

        #expect(result.passed)
        // 3 total, 1 skipped → 2 executed.
        #expect(result.summary.contains("2 executed"))
    }

    @Test("When no .xcresult is parseable, the grader falls back to the exit code")
    func noParseableResultBundle() async throws {
        let runner = FakeProcessRunner()
        // xcodebuild test itself succeeded.
        runner.enqueue(exitCode: 0)
        // xcresulttool returns nothing usable.
        runner.enqueue(exitCode: 1, standardOutput: "tool error: bundle not found\n")
        let (context, workspace) = try await makeGradingContext(processRunner: runner)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let grader = XCTestGrader(configuration: XCTestGraderConfiguration(scheme: "App"))
        let result = try await grader.grade(task: defaultTask(), context: context)

        #expect(result.passed)
        #expect(result.summary.contains("no parseable"))
    }

    @Test("xcodebuild test is invoked with -only-testing and -skip-testing flags")
    func testingFlags() async throws {
        let runner = FakeProcessRunner()
        runner.enqueue(exitCode: 0)
        runner.enqueue(
            exitCode: 0,
            standardOutput: #"{"totalTestCount":1,"passedTests":1,"failedTests":0,"skippedTests":0}"#
        )
        let (context, workspace) = try await makeGradingContext(processRunner: runner)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let grader = XCTestGrader(configuration: XCTestGraderConfiguration(
            scheme: "App",
            testPlan: "Benchmark",
            tests: ["AppTests/testA", "AppTests/testB"],
            skipTests: ["AppTests/testC"]
        ))
        _ = try await grader.grade(task: defaultTask(), context: context)

        let arguments = try #require(xcodebuildCall(runner)).arguments
        #expect(arguments.contains("-testPlan"))
        #expect(arguments.contains("Benchmark"))
        #expect(arguments.contains("-only-testing:AppTests/testA"))
        #expect(arguments.contains("-only-testing:AppTests/testB"))
        #expect(arguments.contains("-skip-testing:AppTests/testC"))
        #expect(arguments.contains("-resultBundlePath"))
        #expect(arguments.contains("test"))
    }

    @Test("The xcuitest identifier is used as the grader name and log file")
    func xcuitestIdentifier() async throws {
        let runner = FakeProcessRunner()
        runner.enqueue(exitCode: 0)
        runner.enqueue(
            exitCode: 0,
            standardOutput: #"{"totalTestCount":1,"passedTests":1,"failedTests":0,"skippedTests":0}"#
        )
        let (context, workspace) = try await makeGradingContext(processRunner: runner)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let grader = XCTestGrader(
            configuration: XCTestGraderConfiguration(scheme: "AppUITests"),
            identifier: "xcuitest"
        )
        let result = try await grader.grade(task: defaultTask(), context: context)

        #expect(result.grader == "xcuitest")
        #expect(result.evidence.contains { $0.name == "xcuitest.log" })
    }
}

@Suite("xcodebuild test grader: isolation and reporting")
struct XCTestGraderIsolationTests {
    private let passingSummary = """
    {"result": "Succeeded", "totalTestCount": 1, "passedTests": 1, "failedTests": 0, "skippedTests": 0}
    """

    @Test("A test target that does not compile is reported as a compile failure, not as no tests")
    func compileFailureIsNamed() async throws {
        let runner = FakeProcessRunner()
        let compileError = """
        /tmp/w/Tests/StoreTests.swift:8:9: error: call can throw but is not marked with 'try'
        ** TEST BUILD FAILED **
        """
        let emptySummary = """
        {"result": "Failed", "totalTestCount": 0, "passedTests": 0, "failedTests": 0, "skippedTests": 0}
        """
        runner.enqueue(exitCode: 65, standardOutput: compileError)
        runner.enqueue(exitCode: 0, standardOutput: emptySummary)
        runner.enqueue(exitCode: 65, standardOutput: compileError)
        runner.enqueue(exitCode: 0, standardOutput: emptySummary)
        let (context, workspace) = try await makeGradingContext(processRunner: runner)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let result = try await XCTestGrader(configuration: XCTestGraderConfiguration(scheme: "App"))
            .grade(task: defaultTask(), context: context)

        #expect(!result.passed)
        #expect(result.summary.contains("Tests failed to compile"))
        #expect(result.summary.contains("call can throw but is not marked with 'try'"))
    }

    @Test("A non-compiler xcodebuild error is not reported as a compile failure")
    func xcodebuildErrorsAreNotCompileErrors() async throws {
        let runner = FakeProcessRunner()
        let failure = "xcodebuild: error: Scheme App is not currently configured for the test action.\n"
        let emptySummary = #"{"result": "Failed", "totalTestCount": 0, "passedTests": 0, "failedTests": 0, "skippedTests": 0}"#
        for _ in 0..<2 {
            runner.enqueue(exitCode: 66, standardError: failure)
            runner.enqueue(exitCode: 0, standardOutput: emptySummary)
        }
        let (context, workspace) = try await makeGradingContext(processRunner: runner)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let result = try await XCTestGrader(configuration: XCTestGraderConfiguration(scheme: "App"))
            .grade(task: defaultTask(), context: context)

        #expect(!result.passed)
        #expect(!result.summary.contains("Tests failed to compile"))
        #expect(result.summary.contains("No tests executed"))
    }

    @Test("Paths named in remove_before are deleted before the tests run")
    func removesStaleFilesBeforeRunning() async throws {
        let runner = FakeProcessRunner()
        runner.enqueue(exitCode: 0)
        runner.enqueue(exitCode: 0, standardOutput: passingSummary)
        let (context, workspace) = try await makeGradingContext(processRunner: runner)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let stale = workspace.appendingPathComponent("snapshot.txt")
        try "written by the agent, not the test".write(to: stale, atomically: true, encoding: .utf8)

        _ = try await XCTestGrader(configuration: XCTestGraderConfiguration(scheme: "App", removeBefore: ["snapshot.txt"]))
            .grade(task: defaultTask(), context: context)

        #expect(!FileManager.default.fileExists(atPath: stale.path))
    }

    @Test("The app under test is uninstalled and its permissions reset before every test run")
    func resetsAppStateBeforeTesting() async throws {
        let runner = FakeProcessRunner()
        runner.setUniversal(exitCode: 0, standardOutput: passingSummary)
        let (context, workspace) = try await makeGradingContext(processRunner: runner, simulatorUDID: "SIM-1")
        defer { try? FileManager.default.removeItem(at: workspace) }
        try writeBuiltApp(named: "Counter", bundleID: "com.applebench.Counter", in: context.derivedDataURL)
        try writeBuiltApp(named: "CounterUITests-Runner", bundleID: "com.apple.test.Runner", in: context.derivedDataURL)

        _ = try await XCTestGrader(configuration: XCTestGraderConfiguration(scheme: "App"))
            .grade(task: defaultTask(), context: context)

        let calls = runner.commands().map { ([$0.executable] + $0.arguments).joined(separator: " ") }
        let testIndex = try #require(calls.firstIndex { $0.contains("xcodebuild") })
        let before = calls[..<testIndex]
        #expect(before.contains("/usr/bin/xcrun simctl uninstall SIM-1 com.applebench.Counter"))
        #expect(before.contains("/usr/bin/xcrun simctl privacy SIM-1 reset all com.applebench.Counter"))
        #expect(!calls.contains { $0.contains("com.apple.test.Runner") })
    }
}

func writeBuiltApp(named name: String, bundleID: String, in derivedData: URL) throws {
    let app = derivedData.appendingPathComponent("Build/Products/Debug-iphonesimulator/\(name).app", isDirectory: true)
    try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
    let plist = try PropertyListSerialization.data(
        fromPropertyList: ["CFBundleIdentifier": bundleID], format: .xml, options: 0
    )
    try plist.write(to: app.appendingPathComponent("Info.plist"))
}
