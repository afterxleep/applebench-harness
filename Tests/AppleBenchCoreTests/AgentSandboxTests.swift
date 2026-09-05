import Foundation
import Testing
@testable import AppleBenchCore

@Suite("Agent sandbox")
struct AgentSandboxTests {
    private func sandbox(
        denied: [String] = ["/answers"],
        workspace: String = "/runs/r1/workspace",
        execRoots: [String] = []
    ) -> AgentSandbox {
        AgentSandbox(
            deniedReadPaths: denied.map { URL(fileURLWithPath: $0) },
            workspaceURL: URL(fileURLWithPath: workspace),
            executableRoots: execRoots.map { URL(fileURLWithPath: $0) }
        )
    }

    @Test("The answers are denied and the workspace is allowed back")
    func deniesAnswersAllowsWorkspace() {
        let profile = sandbox(denied: ["/runs"], workspace: "/runs/r1/workspace").profile()
        let deny = try! #require(profile.range(of: "(deny file-read* (subpath \"/runs\")"))
        let allow = try! #require(profile.range(of: "(allow file-read* (subpath \"/runs/r1/workspace\")"))
        // SBPL takes the last matching rule, so a workspace inside a denied
        // root only opens if its allowance comes after the denial.
        #expect(deny.lowerBound < allow.lowerBound)
    }

    @Test("A denied binary uses a literal rule, not a subpath")
    func deniesBinariesByLiteral() throws {
        // `subpath` matches directory trees; on a file it matches nothing, so
        // a wrapper denied that way would still run.
        let binary = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("applebench-fake-wrapper-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: binary.path, contents: Data("#!/bin/sh\n".utf8))
        defer { try? FileManager.default.removeItem(at: binary) }

        let profile = sandbox(denied: [binary.path]).profile()
        #expect(profile.contains("(deny file-read* (literal \"\(binary.path)\"))"))
        #expect(!profile.contains("(deny file-read* (subpath \"\(binary.path)\"))"))
    }

    @Test("Execution is an allowlist, and it comes last")
    func executionIsAnAllowlist() throws {
        let profile = sandbox(execRoots: ["/usr/bin", "/bin"]).profile()
        let deny = try #require(profile.range(of: "(deny process-exec*)"))
        let allow = try #require(profile.range(of: "(allow process-exec (subpath \"/usr/bin\"))"))
        #expect(deny.lowerBound < allow.lowerBound)
        #expect(profile.contains("(allow process-exec (subpath \"/bin\"))"))
    }

    @Test("No execution rules at all when no roots are given")
    func noExecutionRulesWithoutRoots() {
        // Denying execution with nothing allowed would stop the agent running
        // itself, so an empty list means the rule is not emitted.
        #expect(!sandbox(execRoots: []).profile().contains("process-exec"))
    }

    @Test("The toolchain roots cover Apple's tools and exclude user bins")
    func toolchainRootsAreTheApplePaths() {
        let roots = AgentSandbox.toolchainRoots(agentExecutable: nil, runDirectory: nil)
            .map(\.path)
        for expected in ["/usr/bin", "/bin", "/Library/Developer", "/Applications", "/usr/libexec"] {
            #expect(roots.contains(expected), "missing \(expected)")
        }
        // Homebrew and user bins are where the wrapper CLIs live, and where a
        // replacement would be installed.
        #expect(!roots.contains("/opt/homebrew/bin"))
        #expect(!roots.contains(NSHomeDirectory() + "/.local/bin"))
    }

    @Test("The agent's own binary is allowed to execute")
    func agentBinaryIsExecutable() {
        let agent = URL(fileURLWithPath: "/opt/tools/bin/theagent")
        let roots = AgentSandbox.toolchainRoots(agentExecutable: agent, runDirectory: nil)
            .map(\.path)
        #expect(roots.contains("/opt/tools/bin"))
    }

    @Test("A quote in a path cannot end the rule early")
    func quotesAreEscaped() {
        let profile = sandbox(denied: ["/tmp/we\"ird"]).profile()
        #expect(profile.contains("\\\"ird"))
    }

    @Test("The standard set denies solutions, other runs and the task set")
    func standardDeniesTheAnswers() {
        let box = AgentSandbox.standard(
            harnessRoot: URL(fileURLWithPath: "/h"),
            taskSetRoot: URL(fileURLWithPath: "/tasks"),
            workspaceURL: URL(fileURLWithPath: "/h/.applebench/runs/r1/workspace")
        )
        let denied = box.deniedReadPaths.map(\.path)
        for expected in [
            "/h/.applebench/solutions", "/h/.applebench/fixtures",
            "/h/.applebench/runs", "/h/.applebench/taskset",
            "/h/Sources/AppleBenchGraders", "/tasks",
        ] {
            #expect(denied.contains(expected), "missing \(expected)")
        }
    }

    @Test("Answers are denied wherever they sit, not just under .applebench")
    func answersDeniedAnywhere() {
        // The harness checkout has a tracked `Fixtures/` beside `.applebench`,
        // and every fixture in it carries its own `.solution` and
        // `solution.patch`. Only the prepared copy was denied, so the originals
        // were readable, and a model did go and list one.
        let box = AgentSandbox.standard(
            harnessRoot: URL(fileURLWithPath: "/h"),
            taskSetRoot: nil,
            workspaceURL: URL(fileURLWithPath: "/h/.applebench/runs/r1/workspace")
        )
        #expect(box.deniedReadPaths.map(\.path).contains("/h/Fixtures"))

        // And by shape, for a layout nobody has thought of yet.
        let profile = box.profile()
        #expect(profile.contains("solution"), "no rule mentions a solution at all")
    }

    @Test("The agent cannot write outside its workspace")
    func writesAreConfinedToTheWorkspace() throws {
        // Eleven tasks wrote their deliverable outside the workspace, six of
        // them straight into the operator's checkout. The grader looked in the
        // workspace, found nothing, and failed work the model had done. The
        // toolchain needs a temp directory, so writes cannot be confined to
        // the workspace alone — but the checkout is never writable.
        let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("applebench-write-\(UUID().uuidString)")
        let workspace = scratch.appendingPathComponent("workspace")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let box = AgentSandbox(
            deniedReadPaths: [], workspaceURL: workspace, deniedWritePaths: [scratch]
        )
        let profileURL = scratch.appendingPathComponent("p.sb")

        func canWrite(_ target: URL) throws -> Bool {
            let command = try #require(try box.wrap(
                executable: "/usr/bin/touch", arguments: [target.path], profileURL: profileURL
            ))
            let process = Process()
            process.executableURL = URL(fileURLWithPath: command.executable)
            process.arguments = command.arguments
            process.standardError = FileHandle.nullDevice
            try process.run(); process.waitUntilExit()
            return process.terminationStatus == 0
        }
        #expect(try canWrite(workspace.appendingPathComponent("report.md")))
        #expect(try !canWrite(scratch.appendingPathComponent("escaped.md")))
    }

    @Test("Wrapper binaries are denied without being asked")
    func wrappersAreAlwaysDenied() throws {
        // Denying them was once opt-in, so whether a task measured toolchain
        // skill or wrapper recall depended on a flag being remembered. It is
        // now unconditional, and the prompts no longer mention it.
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("applebench-always-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let wrapper = directory.appendingPathComponent("fastlane")
        FileManager.default.createFile(
            atPath: wrapper.path, contents: Data("#!/bin/sh\n".utf8),
            attributes: [.posixPermissions: 0o755]
        )

        let box = AgentSandbox.standard(
            harnessRoot: URL(fileURLWithPath: "/h"),
            taskSetRoot: nil,
            workspaceURL: URL(fileURLWithPath: "/w"),
            hostPath: directory.path
        )
        #expect(box.deniedReadPaths.map(\.path).contains(wrapper.path))
        // The directory the wrapper lives in is not an execution root either,
        // so a second copy of it there is unreachable too.
        #expect(!box.executableRoots.map(\.path).contains(directory.path))
    }

    @Test("The blocked list covers the ways round the toolchain")
    func blockedListIsBroad() {
        // A task answered with a wrapper measures whether the operator
        // installed it. Each of these is a different route to that.
        for expected in [
            "flowdeck", "tuist", "xcodegen", "fastlane", "swiftlint", "xcpretty",
            "pod", "carthage", "mint", "sourcery", "ios-deploy", "idb", "appium",
            "bazel", "xcodes", "brew", "npm", "gem",
        ] {
            #expect(AgentSandbox.wrapperCLINames.contains(expected), "missing \(expected)")
        }
    }

    @Test("A wrapper on PATH is found and denied, symlink and target both")
    func findsWrappersOnPath() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("applebench-wrappers-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let wrapper = directory.appendingPathComponent("flowdeck")
        FileManager.default.createFile(
            atPath: wrapper.path,
            contents: Data("#!/bin/sh\n".utf8),
            attributes: [.posixPermissions: 0o755]
        )
        let found = AgentSandbox.wrapperBinaries(on: directory.path).map(\.path)
        #expect(found.contains(wrapper.path))
    }

    @Test("An allowed file inside a denied root opens, and its siblings do not")
    func allowedReadEscapesTheDenial() throws {
        // The agent's own config lives in its run directory, outside the
        // workspace so the agent cannot edit its own permissions. That
        // directory is denied wholesale to hide other runs, so the one file it
        // needs has to be allowed back by name.
        let box = sandbox(denied: ["/runs"], workspace: "/runs/r1/workspace")
            .allowingRead([URL(fileURLWithPath: "/runs/r1/opencode.json")])
        let profile = box.profile()
        let deny = try #require(profile.range(of: "(deny file-read* (subpath \"/runs\")"))
        let allow = try #require(
            profile.range(of: "(allow file-read* (literal \"/runs/r1/opencode.json\"))")
        )
        #expect(deny.lowerBound < allow.lowerBound)
        // The answer key sits beside it in the same directory and stays shut.
        #expect(!profile.contains("/runs/r1/metadata.json"))
    }

    @Test("sandbox-exec really opens the allowed file and really shuts its sibling")
    func realSandboxHonoursTheAllowance() throws {
        // Rule order in a string is not the claim. The claim is what the
        // kernel does, and the last time this was only checked as text the
        // agent was denied its own config on every task of a full suite.
        let run = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("applebench-seal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: run.appendingPathComponent("workspace"), withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: run) }

        let config = run.appendingPathComponent("opencode.json")
        let answers = run.appendingPathComponent("metadata.json")
        try "{}".write(to: config, atomically: true, encoding: .utf8)
        try "{}".write(to: answers, atomically: true, encoding: .utf8)

        let box = AgentSandbox(
            deniedReadPaths: [run],
            workspaceURL: run.appendingPathComponent("workspace")
        ).allowingRead([config])
        let profileURL = run.appendingPathComponent("agent.sb")

        func canRead(_ file: URL) throws -> Bool {
            let command = try #require(
                try box.wrap(executable: "/bin/cat", arguments: [file.path], profileURL: profileURL)
            )
            let process = Process()
            process.executableURL = URL(fileURLWithPath: command.executable)
            process.arguments = command.arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        }

        #expect(try canRead(config), "the agent cannot read its own configuration")
        #expect(try !canRead(answers), "the run's grader specification is readable")
    }

    @Test("A binary the agent obtains at a new path cannot run")
    func downloadedBinariesCannotRun() throws {
        // Denying wrappers by name is defeated by fetching one. Copying a
        // denied binary already fails, because reading it is denied — but
        // nothing stopped the agent downloading a fresh one and running it,
        // so execution is an allowlist rather than a list of names.
        let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("applebench-exec-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let tool = scratch.appendingPathComponent("downloaded-wrapper")
        FileManager.default.createFile(
            atPath: tool.path, contents: Data("#!/bin/sh\necho ran\n".utf8),
            attributes: [.posixPermissions: 0o755]
        )
        let box = AgentSandbox(
            deniedReadPaths: [], workspaceURL: scratch,
            executableRoots: [URL(fileURLWithPath: "/bin"), URL(fileURLWithPath: "/usr/bin")]
        )
        let profileURL = scratch.appendingPathComponent("p.sb")
        let command = try #require(
            try box.wrap(executable: tool.path, arguments: [], profileURL: profileURL)
        )
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        #expect(process.terminationStatus != 0, "a downloaded binary was allowed to run")
    }

    @Test("The standard seal restricts execution to the toolchain")
    func standardSealAllowlistsExecution() {
        let box = AgentSandbox.standard(
            harnessRoot: URL(fileURLWithPath: "/h"),
            taskSetRoot: nil,
            workspaceURL: URL(fileURLWithPath: "/h/.applebench/runs/r1/workspace"),
            agentExecutable: URL(fileURLWithPath: "/Users/me/.opencode/bin/opencode"),
            runDirectory: URL(fileURLWithPath: "/h/.applebench/runs/r1")
        )
        let roots = box.executableRoots.map(\.path)
        #expect(roots.contains("/usr/bin"))
        #expect(roots.contains("/Library/Developer"))
        #expect(roots.contains("/Users/me/.opencode/bin"), "the agent cannot run itself")
        #expect(roots.contains("/h/.applebench/runs/r1"), "test binaries the run builds")
        // The workspace is writable, so allowing execution from it would let
        // the agent run anything it managed to write there.
        #expect(!roots.contains("/h/.applebench/runs/r1/workspace"))
        #expect(!roots.contains("/opt/homebrew/bin"))
    }

    @Test("Wrapping produces a sandbox-exec invocation and writes the profile")
    func wrapWritesProfile() throws {
        let profileURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("applebench-profile-\(UUID().uuidString).sb")
        defer { try? FileManager.default.removeItem(at: profileURL) }

        let wrapped = try sandbox().wrap(
            executable: "/usr/bin/true",
            arguments: ["--flag"],
            profileURL: profileURL
        )
        let command = try #require(wrapped)
        #expect(command.executable == AgentSandbox.sandboxExec)
        #expect(command.arguments == ["-f", profileURL.path, "/usr/bin/true", "--flag"])
        #expect(FileManager.default.fileExists(atPath: profileURL.path))
    }
}

@Suite("Adapter executable dispatch")
struct AdapterExecutableTests {
    private struct Located: AgentAdapter {
        let identifier = "located"
        let telemetry = AgentTelemetryCapability.plainText
        var executableURL: URL? { URL(fileURLWithPath: "/opt/tools/bin/agent") }
        func prepare(context: RunContext) async throws {}
        func run(task: BenchmarkTask, context: RunContext, recorder: EventRecorder) async throws -> AgentRunResult {
            AgentRunResult(
                metadata: AgentMetadata(agent: identifier, model: nil as String?, version: nil, configuration: [:]),
                terminationReason: .completed
            )
        }
        func cleanup(context: RunContext) async {}
    }

    @Test("An adapter's own binary is visible through the protocol")
    func executableIsDynamicallyDispatched() {
        // It lived only in a protocol extension, so a call through `any
        // AgentAdapter` bound to the extension's nil and the adapter's answer
        // was never asked for. Nothing noticed while the sandbox let
        // everything execute; with an allowlist it stops the agent running
        // itself.
        let adapter: any AgentAdapter = Located()
        #expect(adapter.executableURL?.path == "/opt/tools/bin/agent")
    }
}
