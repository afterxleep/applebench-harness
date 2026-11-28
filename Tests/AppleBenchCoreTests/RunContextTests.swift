import Foundation
import Testing
@testable import AppleBenchCore

@Suite("Run context")
struct RunContextTests {
    @Test("filterWrapperCLIs removes xcodegen and other wrappers from PATH")
    func stripsXcodegen() {
        // Simulate a PATH that includes a directory with xcodegen + a
        // harmless binary, plus a clean directory.
        let dirWithWrappers = FileManager.default.temporaryDirectory
            .appendingPathComponent("applebench-runcontext-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(
            at: dirWithWrappers, withIntermediateDirectories: true
        )
        let xcodegenStub = dirWithWrappers.appendingPathComponent("xcodegen")
        let claudeStub = dirWithWrappers.appendingPathComponent("claude")
        for path in [xcodegenStub, claudeStub] {
            try? FileManager.default.removeItem(at: path)
        }
        // Touch the files so the FileManager.isExecutableFile check passes.
        FileManager.default.createFile(atPath: xcodegenStub.path, contents: Data())
        FileManager.default.createFile(atPath: claudeStub.path, contents: Data())
        defer {
            try? FileManager.default.removeItem(at: dirWithWrappers)
        }

        let cleanDir = "/usr/bin"
        let path = "\(dirWithWrappers.path):\(cleanDir)"
        let filtered = RunContext.filterWrapperCLIs(
            from: path, agentBinaryNames: ["claude"]
        )

        // The agent-binary directory must be preserved even though it
        // also contains xcodegen — without the agent, nothing runs.
        #expect(filtered.contains(dirWithWrappers.path))
        // The clean directory survives.
        #expect(filtered.contains(cleanDir))
    }

    @Test("A sealed agent disables the compiler's nested plugin sandbox")
    func sealedAgentDisablesNestedSwiftPluginSandbox() {
        let workspace = URL(fileURLWithPath: "/tmp/applebench-workspace")
        let context = RunContext(
            runID: "test",
            workspaceURL: workspace,
            runDirectoryURL: URL(fileURLWithPath: "/tmp/applebench-run"),
            logsDirectoryURL: URL(fileURLWithPath: "/tmp/applebench-run/logs"),
            model: "model",
            sandbox: AgentSandbox(deniedReadPaths: [], workspaceURL: workspace),
            limits: RunLimits(),
            environment: EnvironmentSnapshot(
                macosVersion: "26.5",
                architecture: "arm64",
                xcodePath: "/Applications/Xcode.app/Contents/Developer",
                xcodeVersion: "27.0",
                xcodeBuildNumber: "27A0000"
            )
        )

        let environment = context.agentEnvironment()

        #expect(environment["OTHER_SWIFT_FLAGS"]?.contains("-disable-sandbox") == true)
        #expect(environment["XBS_DISABLE_SANDBOXED_BUILDS"] == "1")
    }

    @Test("A hermetic agent keeps temporary executables inside its own home")
    func hermeticAgentOwnsItsTemporaryDirectory() {
        let workspace = URL(fileURLWithPath: "/tmp/applebench-workspace")
        let home = URL(fileURLWithPath: "/tmp/applebench-agent-home")
        let context = RunContext(
            runID: "test",
            workspaceURL: workspace,
            runDirectoryURL: URL(fileURLWithPath: "/tmp/applebench-run"),
            logsDirectoryURL: URL(fileURLWithPath: "/tmp/applebench-run/logs"),
            model: "model",
            sandbox: AgentSandbox(deniedReadPaths: [], workspaceURL: workspace),
            limits: RunLimits(),
            environment: EnvironmentSnapshot(
                macosVersion: "26.5",
                architecture: "arm64",
                xcodePath: "/Applications/Xcode.app/Contents/Developer",
                xcodeVersion: "27.0",
                xcodeBuildNumber: "27A0000"
            )
        )

        let environment = context.agentEnvironment(hermeticHome: home)

        #expect(environment["TMPDIR"] == home.appendingPathComponent("tmp").path)
    }
}
