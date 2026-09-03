import Foundation

/// A macOS sandbox profile that seals an agent inside its own workspace.
///
/// Stripping wrapper CLIs from `PATH` stops an agent *reaching* for a tool it
/// should not use. It does nothing about the far cheaper cheat: the answers
/// are on the same filesystem, and the agent runs as the same user. Every
/// fixture ships a `.solution` directory, every task file names its graders
/// and its mutation targets, and both sit a `cat` away from a process that is
/// supposed to be solving the task from scratch.
///
/// So the paths that hold answers are denied, and the workspace is allowed
/// back inside that denial. Reading, not writing, is what matters here: an
/// agent that copies a reference patch into its workspace has not solved
/// anything, and nothing in the run would have noticed.
///
/// What this does not do is take the network away. OpenCode reaches the model
/// over HTTPS from the same process tree as its bash tool, and a sandbox
/// profile is inherited by children, so denying egress here denies the agent
/// its own model. Egress is enforced by running under `--vm`, which is the
/// only mode that can honestly claim it.
public struct AgentSandbox: Sendable {
    /// Directories whose contents would answer the task.
    public let deniedReadPaths: [URL]
    /// The one place the agent is expected to work, allowed back after the
    /// denials above so a workspace living under a denied root still opens.
    public let workspaceURL: URL
    /// Roots the agent may execute from. Everything else is refused.
    ///
    /// This is the rule that survives an agent with imagination. Denying a
    /// wrapper by name assumes it stays where it was found; denying execution
    /// everywhere except the toolchain means a copy, a download, a build of
    /// its own, and a script it writes in /tmp all fail the same way.
    public let executableRoots: [URL]

    public init(deniedReadPaths: [URL], workspaceURL: URL, executableRoots: [URL] = []) {
        self.deniedReadPaths = deniedReadPaths
        self.workspaceURL = workspaceURL
        self.executableRoots = executableRoots
    }

    /// Where a legitimate Apple-platform run needs to execute from.
    ///
    /// The Apple toolchain, the standard Unix tools it shells out to, and the
    /// agent's own binary. Deliberately not Homebrew or any user bin: that is
    /// where the wrapper CLIs live, and where a fresh one would be installed.
    public static func toolchainRoots(
        agentExecutable: URL?,
        runDirectory: URL?
    ) -> [URL] {
        var roots = [
            "/bin", "/sbin", "/usr/bin", "/usr/sbin", "/usr/libexec",
            "/System", "/Library/Developer", "/Applications",
        ].map { URL(fileURLWithPath: $0) }
        if let agentExecutable {
            // The agent runs from wherever it was installed, and its runtime
            // usually sits beside it.
            roots.append(agentExecutable.resolvingSymlinksInPath().deletingLastPathComponent())
        }
        if let runDirectory {
            // Test binaries and build products the run itself produces.
            roots.append(runDirectory)
        }
        return roots
    }

    /// The paths worth denying for a run, given where things live.
    ///
    /// - Parameters:
    ///   - harnessRoot: the checkout holding `.applebench` and the graders.
    ///   - taskSetRoot: the task set, when one is configured. It holds every
    ///     fixture's `.solution` and every task's grader configuration.
    ///   - workspaceURL: the agent's checkout.
    /// Wrapper CLIs that answer an Apple task by wrapping the toolchain.
    /// Denying the binary is what actually removes one: taking it off `PATH`
    /// only stops the agent typing its name, and `/Users/me/.local/bin/flowdeck`
    /// still runs, as does a copy of it the agent makes somewhere else.
    public static let wrapperCLINames = [
        "flowdeck", "tuist", "xcbeautify", "xcbeautify-tests", "fastlane",
        "swift-package-bundler", "periphery", "swiftlint", "xcodegen",
    ]

    /// Every wrapper binary reachable from a PATH, resolved to a real file.
    static func wrapperBinaries(on path: String) -> [URL] {
        let fm = FileManager.default
        var found: [URL] = []
        for directory in path.split(separator: ":").map(String.init) {
            for name in wrapperCLINames {
                let candidate = "\(directory)/\(name)"
                guard fm.isExecutableFile(atPath: candidate) else { continue }
                let resolved = URL(fileURLWithPath: candidate).resolvingSymlinksInPath()
                found.append(URL(fileURLWithPath: candidate))
                if resolved.path != candidate { found.append(resolved) }
            }
        }
        return found
    }

    public static func standard(
        harnessRoot: URL,
        taskSetRoot: URL?,
        workspaceURL: URL,
        denyWrapperCLIs: Bool = false,
        hostPath: String = ProcessInfo.processInfo.environment["PATH"] ?? "",
        agentExecutable: URL? = nil,
        runDirectory: URL? = nil
    ) -> AgentSandbox {
        var denied: [URL] = [
            // Reference fixes, applied by the `solution` agent.
            harnessRoot.appendingPathComponent(".applebench/solutions"),
            // The prepared fixtures, which carry `.solution` with them.
            harnessRoot.appendingPathComponent(".applebench/fixtures"),
            // Other runs: their result.json says which graders passed, and
            // their workspaces hold finished work for the same tasks.
            harnessRoot.appendingPathComponent(".applebench/runs"),
            // The task set clone, when it lives inside the harness.
            harnessRoot.appendingPathComponent(".applebench/taskset"),
            // The graders themselves. Knowing exactly what is asserted is
            // most of the way to satisfying it without doing the work.
            harnessRoot.appendingPathComponent("Sources/AppleBenchGraders"),
            harnessRoot.appendingPathComponent("Reports"),
        ]
        if let taskSetRoot {
            denied.append(taskSetRoot)
        }
        if denyWrapperCLIs {
            denied.append(contentsOf: wrapperBinaries(on: hostPath))
        }
        // Execution stays open. Every tool on the machine is fair game except
        // the wrappers denied above, because a benchmark that also refuses
        // whatever the operator happens to have installed is measuring the
        // machine, not the model. `executableRoots` remains available for a
        // run that wants the stricter reading; nothing sets it by default.
        _ = (agentExecutable, runDirectory)
        return AgentSandbox(deniedReadPaths: denied, workspaceURL: workspaceURL)
    }

    /// The sandbox profile, in Apple's SBPL.
    ///
    /// `allow default` first, because the alternative is enumerating every
    /// path a Swift toolchain touches and discovering the gaps one broken
    /// build at a time. The rules that follow subtract from it, and SBPL takes
    /// the last matching rule, so the workspace allowance has to come after
    /// the denials that contain it.
    public func profile() -> String {
        var lines = [
            "(version 1)",
            "(allow default)",
        ]
        let fm = FileManager.default
        for path in deniedReadPaths {
            var isDirectory: ObjCBool = false
            let exists = fm.fileExists(atPath: path.path, isDirectory: &isDirectory)
            // `subpath` on a file matches nothing, so a binary needs `literal`.
            // Denying read also denies exec: a binary has to be read to run,
            // and it has to be read to be copied somewhere the rule misses.
            let rule = (exists && !isDirectory.boolValue) ? "literal" : "subpath"
            lines.append("(deny file-read* (\(rule) \(quote(path.path))))")
        }
        // The workspace usually lives under `.applebench/runs`, which was just
        // denied wholesale. Allowing it back is what makes the run possible.
        lines.append("(allow file-read* (subpath \(quote(workspaceURL.path))))")
        lines.append("(allow file-write* (subpath \(quote(workspaceURL.path))))")

        // Execution last, and as an allowlist. Refusing every binary outside
        // the toolchain is what stops the agent routing around a denied
        // wrapper: copying it, downloading another, or writing its own.
        if !executableRoots.isEmpty {
            lines.append("(deny process-exec*)")
            for root in executableRoots {
                lines.append("(allow process-exec (subpath \(quote(root.path))))")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Writes the profile and returns the command that runs `command` under it.
    ///
    /// Returns `nil` when the platform has no `sandbox-exec`, so a run on a
    /// machine without it fails loudly at the caller rather than silently
    /// dropping the seal.
    public func wrap(
        executable: String,
        arguments: [String],
        profileURL: URL
    ) throws -> (executable: String, arguments: [String])? {
        guard FileManager.default.isExecutableFile(atPath: Self.sandboxExec) else { return nil }
        try profile().write(to: profileURL, atomically: true, encoding: .utf8)
        return (Self.sandboxExec, ["-f", profileURL.path, executable] + arguments)
    }

    public static let sandboxExec = "/usr/bin/sandbox-exec"

    /// SBPL string literal. A path with a quote in it would otherwise end the
    /// literal early and change what the rule denies.
    private func quote(_ path: String) -> String {
        "\"" + path.replacingOccurrences(of: "\\", with: "\\\\")
                   .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
