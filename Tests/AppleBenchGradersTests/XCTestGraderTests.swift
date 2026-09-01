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

    @Test("Zero executed tests is a FAIL — a run that did not run proves nothing")
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
        #expect(result.summary.contains("no tests executed"))
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
            standardOutput: #"{"totalTestCount":0,"passedTests":0,"failedTests":0,"skippedTests":0}"#
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
