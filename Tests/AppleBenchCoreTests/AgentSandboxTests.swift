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

    @Test("A binary the agent fetches into its workspace may run")
    func downloadedBinariesMayRun() throws {
        // A tool the agent downloads is its own work: it pays the tokens to
        // find, fetch and drive it, and the deliverable is still judged by the
        // graders that look at it. What stays refused is a wrapper already
        // installed on this machine, so a score does not move with the
        // operator's setup.
        let run = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("applebench-run-\(UUID().uuidString)")
        let workspace = run.appendingPathComponent("workspace")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: run) }
        let tool = workspace.appendingPathComponent("fetched-tool")
        FileManager.default.createFile(
            atPath: tool.path, contents: Data("#!/bin/sh\necho ran\n".utf8),
            attributes: [.posixPermissions: 0o755]
        )
        let box = AgentSandbox.standard(
            harnessRoot: URL(fileURLWithPath: "/h"), taskSetRoot: nil,
            workspaceURL: workspace, runDirectory: run
        )
        let profileURL = run.appendingPathComponent("p.sb")
        let command = try #require(try box.wrap(executable: tool.path, arguments: [], profileURL: profileURL))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        #expect(process.terminationStatus == 0, "a tool the agent fetched was refused")
    }

    @Test("SwiftPM can execute a generated package manifest in a sealed run")
    func swiftPackageManifestMayRun() throws {
        let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("applebench-swiftpm-\(UUID().uuidString)")
        let run = scratch.appendingPathComponent(".applebench/runs/r1")
        let workspace = run.appendingPathComponent("workspace")
        let siblingResult = scratch.appendingPathComponent(
            ".applebench/runs/r2/result.json"
        )
        let home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("applebench-swiftpm-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: workspace.appendingPathComponent("Sources/Probe"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: siblingResult.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "answer".write(to: siblingResult, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent("tmp"),
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: scratch)
            try? FileManager.default.removeItem(at: home)
        }

        try """
        // swift-tools-version: 6.0
        import PackageDescription
        let package = Package(name: "Probe", targets: [.executableTarget(name: "Probe")])
        """.write(
            to: workspace.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )
        try "print(\"probe\")\n".write(
            to: workspace.appendingPathComponent("Sources/Probe/main.swift"),
            atomically: true,
            encoding: .utf8
        )

        let box = AgentSandbox.standard(
            harnessRoot: scratch,
            taskSetRoot: nil,
            workspaceURL: workspace,
            runDirectory: run
        ).allowingExecution([home])
        let context = RunContext(
            runID: "test",
            workspaceURL: workspace,
            runDirectoryURL: run,
            logsDirectoryURL: run.appendingPathComponent("logs"),
            model: nil,
            sandbox: box,
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
        let siblingCommand = try #require(try box.wrap(
            executable: "/bin/cat",
            arguments: [siblingResult.path],
            profileURL: scratch.appendingPathComponent("sibling.sb")
        ))
        let siblingProcess = Process()
        siblingProcess.executableURL = URL(fileURLWithPath: siblingCommand.executable)
        siblingProcess.arguments = siblingCommand.arguments
        siblingProcess.environment = environment
        siblingProcess.standardOutput = FileHandle.nullDevice
        siblingProcess.standardError = FileHandle.nullDevice
        try siblingProcess.run()
        siblingProcess.waitUntilExit()
        #expect(
            siblingProcess.terminationStatus != 0,
            "Allowing SwiftPM reopened another run's result"
        )

        let chdirCommand = try #require(try box.wrap(
            executable: "/bin/sh",
            arguments: ["-c", "cd \"$1\" && /bin/pwd", "sh", workspace.path],
            profileURL: scratch.appendingPathComponent("chdir.sb")
        ))
        let chdirProcess = Process()
        chdirProcess.executableURL = URL(fileURLWithPath: chdirCommand.executable)
        chdirProcess.arguments = chdirCommand.arguments
        chdirProcess.environment = environment
        let chdirErrors = Pipe()
        chdirProcess.standardOutput = FileHandle.nullDevice
        chdirProcess.standardError = chdirErrors
        try chdirProcess.run()
        chdirProcess.waitUntilExit()
        let chdirErrorText = String(
            decoding: chdirErrors.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        #expect(
            chdirProcess.terminationStatus == 0,
            "A sealed child could not enter its workspace: \(chdirErrorText)"
        )

        let targetInfoCommand = try #require(try box.wrap(
            executable: "/usr/bin/swiftc",
            arguments: ["-print-target-info"],
            profileURL: scratch.appendingPathComponent("target-info.sb")
        ))
        let targetInfoProcess = Process()
        targetInfoProcess.executableURL = URL(fileURLWithPath: targetInfoCommand.executable)
        targetInfoProcess.arguments = targetInfoCommand.arguments
        targetInfoProcess.environment = environment
        targetInfoProcess.currentDirectoryURL = workspace
        let targetInfoOutput = Pipe()
        let targetInfoErrors = Pipe()
        targetInfoProcess.standardOutput = targetInfoOutput
        targetInfoProcess.standardError = targetInfoErrors
        try targetInfoProcess.run()
        targetInfoProcess.waitUntilExit()
        let targetInfoText = String(
            decoding: targetInfoOutput.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        ) + String(
            decoding: targetInfoErrors.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        #expect(
            targetInfoProcess.terminationStatus == 0,
            "The sealed Swift compiler could not inspect its target: \(targetInfoText)"
        )

        let command = try #require(try box.wrap(
            executable: "/usr/bin/swift",
            arguments: ["build", "--disable-sandbox", "--package-path", workspace.path],
            profileURL: scratch.appendingPathComponent("agent.sb")
        ))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments
        process.environment = environment
        let errors = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        let errorText = String(
            decoding: errors.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )

        #expect(process.terminationStatus == 0, "SwiftPM was blocked by the outer seal: \(errorText)")
    }

    @Test("Xcode can resolve a local package in a sealed run")
    func xcodeCanResolveLocalPackage() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixture = repositoryRoot.appendingPathComponent(
            ".applebench/fixtures/LinkErrorFixture"
        )
        guard FileManager.default.fileExists(atPath: fixture.path) else { return }

        let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("applebench-xcode-\(UUID().uuidString)")
        let run = scratch.appendingPathComponent(".applebench/runs/r1")
        let workspace = run.appendingPathComponent("workspace")
        let home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("applebench-xcode-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: run, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixture, to: workspace)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: scratch)
            try? FileManager.default.removeItem(at: home)
        }

        let box = AgentSandbox.standard(
            harnessRoot: scratch,
            taskSetRoot: nil,
            workspaceURL: workspace,
            runDirectory: run
        ).allowingExecution([home])
        let context = RunContext(
            runID: "test",
            workspaceURL: workspace,
            runDirectoryURL: run,
            logsDirectoryURL: run.appendingPathComponent("logs"),
            model: nil,
            sandbox: box,
            limits: RunLimits(),
            environment: EnvironmentSnapshot(
                macosVersion: "26.5",
                architecture: "arm64",
                xcodePath: "/Applications/Xcode.app/Contents/Developer",
                xcodeVersion: "27.0",
                xcodeBuildNumber: "27A0000"
            )
        )
        let command = try #require(try box.wrap(
            executable: "/bin/sh",
            arguments: [
                "-c",
                "/usr/bin/xcodebuild "
                    + "-IDEPackageSupportDisableManifestSandbox=1 "
                    + "-IDEPackageSupportDisablePluginExecutionSandbox=1 "
                    + "-project LinkErrorFixture.xcodeproj -list"
            ],
            profileURL: scratch.appendingPathComponent("agent.sb")
        ))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments
        process.currentDirectoryURL = workspace
        process.environment = context.agentEnvironment(hermeticHome: home)
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let text = String(
            decoding: output.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        #expect(
            process.terminationStatus == 0
                && !text.contains("sandbox_apply")
                && !text.contains("Unable to set working directory"),
            "Xcode package resolution was blocked by the outer seal: \(text)"
        )
    }

    @Test("A binary somewhere the agent does not control still cannot run")
    func strayBinariesCannotRun() throws {
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

    @Test("An adapter can open an execution root the allowlist could not know about")
    func adapterAddsExecutionRoot() throws {
        // OpenCode extracts ripgrep into its home at first use. The allowlist
        // is built before that home exists, so it refused the binary and the
        // agent's grep tool failed on every task.
        let box = sandbox(execRoots: ["/usr/bin"])
            .allowingExecution([URL(fileURLWithPath: "/tmp/home/.cache/opencode/bin")])
        let profile = box.profile()
        let deny = try #require(profile.range(of: "(deny process-exec*)"))
        let allow = try #require(profile.range(of: "(allow process-exec (subpath \"/tmp/home/.cache/opencode/bin\"))"))
        #expect(deny.lowerBound < allow.lowerBound)
    }

    @Test("An adapter can allow one helper executable without opening its directory")
    func adapterAddsExactExecutable() {
        let box = sandbox(execRoots: ["/usr/bin"])
            .allowingExecution(of: [URL(fileURLWithPath: "/opt/runtime/bin/rg")])
        let profile = box.profile()

        #expect(profile.contains("(allow process-exec (literal \"/opt/runtime/bin/rg\"))"))
        #expect(!profile.contains("(allow process-exec (subpath \"/opt/runtime/bin\"))"))
    }

    @Test("Adding an execution root to an open sandbox keeps it open")
    func executionRootOnOpenSandboxIsNoop() {
        // No allowlist means everything may run already; adding a root must
        // not switch the allowlist on and shut everything else.
        let box = sandbox(execRoots: []).allowingExecution([URL(fileURLWithPath: "/x")])
        #expect(!box.profile().contains("process-exec"))
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
