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

    @Test("Wrapper binaries are only denied when wrapper stripping is on")
    func wrappersDeniedOnlyWhenAsked() {
        let open = AgentSandbox.standard(
            harnessRoot: URL(fileURLWithPath: "/h"),
            taskSetRoot: nil,
            workspaceURL: URL(fileURLWithPath: "/w"),
            denyWrapperCLIs: false
        )
        #expect(open.executableRoots.isEmpty)

        // Denying wrappers denies their binaries; it does not shrink the set
        // of tools the machine offers.
        let sealed = AgentSandbox.standard(
            harnessRoot: URL(fileURLWithPath: "/h"),
            taskSetRoot: nil,
            workspaceURL: URL(fileURLWithPath: "/w"),
            denyWrapperCLIs: true,
            hostPath: "/usr/bin:/bin"
        )
        #expect(sealed.executableRoots.isEmpty)
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
