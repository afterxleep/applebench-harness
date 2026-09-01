import AppleBenchCore
import Foundation
import Testing
@testable import AppleBenchGraders

@Suite("Build grader")
struct BuildGraderTests {

    @Test("An xcodebuild exit code of zero is a PASS")
    func passingBuild() async throws {
        let runner = FakeProcessRunner()
        runner.enqueue(exitCode: 0, standardOutput: "** BUILD SUCCEEDED **\n")
        let (context, workspace) = try await makeGradingContext(processRunner: runner)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let grader = BuildGrader(configuration: BuildGraderConfiguration(
            project: "App.xcodeproj",
            scheme: "App"
        ))
        let result = try await grader.grade(task: defaultTask(), context: context)

        #expect(result.passed)
        #expect(result.grader == "build")
        #expect(result.summary.contains("App"))
        #expect(result.summary.contains("succeeded"))
        // The log is preserved as evidence.
        #expect(result.evidence.contains { $0.name == "build.log" })
    }

    @Test("A non-zero xcodebuild exit code is a FAIL, not an infrastructure error")
    func failingBuild() async throws {
        let runner = FakeProcessRunner()
        runner.enqueue(exitCode: 65, standardError: "error: type 'X' has no member 'Y'\n")
        let (context, workspace) = try await makeGradingContext(processRunner: runner)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let grader = BuildGrader(configuration: BuildGraderConfiguration(
            project: "App.xcodeproj",
            scheme: "App"
        ))
        let result = try await grader.grade(task: defaultTask(), context: context)

        #expect(!result.passed)
        #expect(result.summary.contains("failed"))
        #expect(result.summary.contains("65"))
    }

    @Test("xcodebuild is invoked with the task's project, scheme, and fresh derived data")
    func invokesXcodebuild() async throws {
        let runner = FakeProcessRunner()
        runner.enqueue(exitCode: 0)
        let (context, workspace) = try await makeGradingContext(processRunner: runner)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let grader = BuildGrader(configuration: BuildGraderConfiguration(
            project: "App.xcodeproj",
            scheme: "App",
            configuration: "Release",
            destination: "platform=iOS Simulator,name=iPhone 17,OS=26.5"
        ))
        _ = try await grader.grade(task: defaultTask(), context: context)

        let command = try #require(runner.lastCommand())
        #expect(command.executable == "/usr/bin/xcodebuild")
        #expect(command.arguments.contains("-project"))
        #expect(command.arguments.contains("App.xcodeproj"))
        #expect(command.arguments.contains("-scheme"))
        #expect(command.arguments.contains("App"))
        #expect(command.arguments.contains("-configuration"))
        #expect(command.arguments.contains("Release"))
        #expect(command.arguments.contains("-destination"))
        #expect(command.arguments.contains("platform=iOS Simulator,name=iPhone 17,OS=26.5"))
        // Fresh derived data so the agent's build state cannot leak in.
        #expect(command.arguments.contains("-derivedDataPath"))
        #expect(command.arguments.contains("build"))
        // The result bundle is requested so the .xcresult is available as
        // evidence.
        #expect(command.arguments.contains("-resultBundlePath"))
    }

    @Test("A workspace path takes precedence over a project path")
    func workspaceOverridesProject() async throws {
        let runner = FakeProcessRunner()
        runner.enqueue(exitCode: 0)
        let (context, workspace) = try await makeGradingContext(processRunner: runner)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let grader = BuildGrader(configuration: BuildGraderConfiguration(
            project: "App.xcodeproj",
            workspace: "App.xcworkspace",
            scheme: "App"
        ))
        _ = try await grader.grade(task: defaultTask(), context: context)

        let arguments = try #require(runner.lastCommand()).arguments
        // Either the workspace or the project is passed, but never both
        // (xcodebuild rejects a combined -project and -workspace).
        let hasWorkspace = arguments.contains("-workspace")
        let hasProject = arguments.contains("-project")
        #expect(hasWorkspace)
        #expect(!hasProject)
    }
}
