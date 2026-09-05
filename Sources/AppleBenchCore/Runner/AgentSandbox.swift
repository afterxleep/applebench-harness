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
    /// Individual files allowed back out of those denials.
    ///
    /// An agent's own configuration is written to its run directory rather than
    /// its workspace, so the agent cannot edit its own permissions. That
    /// directory is denied wholesale because it also holds the task's grader
    /// specification and every other run's results, so the one file the agent
    /// legitimately needs is named here rather than opening the directory.
    public let allowedReadPaths: [URL]
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
    /// Places the agent must never write, whatever else is allowed.
    ///
    /// The toolchain needs a temp directory, so writes cannot be confined to
    /// the workspace alone. These are named last so no earlier allowance can
    /// re-open them: the operator's own checkout and the task set.
    public let deniedWritePaths: [URL]

    public init(
        deniedReadPaths: [URL],
        workspaceURL: URL,
        executableRoots: [URL] = [],
        allowedReadPaths: [URL] = [],
        deniedWritePaths: [URL] = []
    ) {
        self.deniedReadPaths = deniedReadPaths
        self.workspaceURL = workspaceURL
        self.executableRoots = executableRoots
        self.allowedReadPaths = allowedReadPaths
        self.deniedWritePaths = deniedWritePaths
    }

    /// A copy that also lets the agent read `paths`.
    ///
    /// Each adapter knows which files it puts outside the workspace; the
    /// standard denial set cannot, so it asks rather than guessing at names.
    public func allowingRead(_ paths: [URL]) -> AgentSandbox {
        AgentSandbox(
            deniedReadPaths: deniedReadPaths,
            workspaceURL: workspaceURL,
            executableRoots: executableRoots,
            allowedReadPaths: allowedReadPaths + paths,
            deniedWritePaths: deniedWritePaths
        )
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
    /// Third-party tools that answer an Apple task by wrapping the toolchain.
    ///
    /// Denying the binary is what actually removes one: taking it off `PATH`
    /// only stops the agent typing its name, and `/Users/me/.local/bin/flowdeck`
    /// still runs, as does a copy of it the agent makes somewhere else.
    ///
    /// The benchmark asks whether a model knows Apple's own toolchain. A task
    /// answered with a wrapper measured whether the operator had installed it,
    /// so the list is deliberately broad: project generators, build wrappers,
    /// dependency managers, release automation, code generators, linters,
    /// device bridges, and the runtime managers that would install any of the
    /// above mid-run.
    public static let wrapperCLINames = [
        // Harnesses and wrappers around xcodebuild
        "flowdeck", "tuist", "xcbeautify", "xcbeautify-tests", "xcpretty",
        "xcodebuild-pretty", "bcsymbolmap", "xcbuild", "buck", "buck2", "bazel",
        "bazelisk", "xctool", "swift-package-bundler",
        // Project generation and manipulation
        "xcodegen", "xcodeproj", "struct", "xcake", "xcconfig",
        // Dependency managers
        "pod", "cocoapods", "carthage", "mint", "accio", "rome", "punic",
        // Release, signing and distribution automation
        "fastlane", "match", "gym", "sigh", "pilot", "deliver", "scan", "snapshot",
        "frameit", "produce", "cert", "spaceship", "supply", "screengrab",
        "bundletool", "sentry-cli", "firebase", "appcenter", "shipit",
        // Code generation, linting and analysis
        "swiftlint", "swiftformat", "swift-format", "sourcery", "swiftgen",
        "periphery", "sourcekitten", "jazzy", "tailor", "infer", "danger",
        // Device and simulator bridges
        "ios-deploy", "idb", "idb_companion", "libimobiledevice", "ideviceinstaller",
        "idevicesyslog", "ideviceinfo", "cfgutil", "appium", "maestro", "detox",
        "waldo", "xcuitest-runner",
        // Runtime and toolchain managers, which would install any of the above
        "mise", "asdf", "rbenv", "rvm", "nodenv", "pyenv", "swiftenv",
        "xcodes", "xcversion",
        // Package managers that would fetch a replacement mid-run
        "brew", "port", "gem", "npm", "npx", "pnpm", "yarn", "bun", "pipx",
    ]

    /// Names too ordinary to look for in command text.
    ///
    /// Denying these as paths is free of doubt, because that check looks at
    /// real files. Matching them in what the agent typed is not: `struct` is
    /// a Swift keyword, `scan` and `match` and `produce` are English, and a
    /// heredoc writing Swift source is full of them. They stay denied and are
    /// simply not evidence.
    public static let ambiguousWrapperNames: Set<String> = [
        "struct", "match", "cert", "produce", "scan", "snapshot", "deliver",
        "pilot", "supply", "gym", "sigh", "frameit", "rome", "port", "infer",
        "danger", "firebase", "shipit", "accio", "punic", "tailor", "xcconfig",
        "bun", "time", "command", "exec", "run",
    ]

    /// The wrapper names it is safe to recognise in a command the agent typed.
    public static var distinctiveWrapperNames: Set<String> {
        Set(wrapperCLINames).subtracting(ambiguousWrapperNames)
    }

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
            // The fixtures as authored, which is where `.solution` and
            // `solution.patch` actually live. Denying only the prepared copy
            // under `.applebench` left the originals open, and a model did go
            // and list one.
            harnessRoot.appendingPathComponent("Fixtures"),
        ]
        if let taskSetRoot {
            denied.append(taskSetRoot)
        }
        // Unconditional. Whether a task measured toolchain skill or wrapper
        // recall used to depend on a flag being passed, and the tasks
        // compensated by saying "no third-party CLI" in the prompt, which told
        // the model such tools existed and were worth reaching for.
        denied.append(contentsOf: wrapperBinaries(on: hostPath))
        // Denying binaries by name only holds while the agent uses the names.
        // Copying a denied one already fails, because reading it is denied,
        // but nothing stopped the agent fetching a fresh wrapper and running
        // that — and on a host run it has the network to do it. So execution
        // is an allowlist: Apple's toolchain, the agent's own binary, and the
        // products this run builds. Deliberately not the workspace, which the
        // agent can write to, and not Homebrew or any user bin.
        return AgentSandbox(
            deniedReadPaths: denied,
            workspaceURL: workspaceURL,
            executableRoots: toolchainRoots(
                agentExecutable: agentExecutable, runDirectory: runDirectory
            ),
            deniedWritePaths: [harnessRoot] + (taskSetRoot.map { [$0] } ?? [])
        )
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
            for spelling in spellings(of: path) {
                lines.append("(deny file-read* (\(rule) \(quote(spelling))))")
            }
        }
        // By shape as well as by path, for a layout nobody has thought of
        // yet. A reference fix is always one of these two names, wherever the
        // directory holding it ends up.
        lines.append(#"(deny file-read* (regex "/\.solution(/|$)"))"#)
        lines.append(#"(deny file-read* (regex "/solution\.patch$"))"#)

        // Named files first, then the workspace. Both sit under a root that
        // was just denied wholesale, and both have to come after it.
        for path in allowedReadPaths {
            for spelling in spellings(of: path) {
                lines.append("(allow file-read* (literal \(quote(spelling))))")
            }
        }
        // Writing is confined to the workspace. Eleven tasks in one suite put
        // their deliverable somewhere else, six of them straight into the
        // operator's own checkout: the grader looked in the workspace, found
        // nothing, and failed work the model had done. A denied write fails
        // loudly enough for the agent to try again in the right place.
        lines.append("(deny file-write*)")
        for spelling in spellings(of: workspaceURL) {
            lines.append("(allow file-read* (subpath \(quote(spelling))))")
            lines.append("(allow file-write* (subpath \(quote(spelling))))")
        }
        // The agent's own scratch space and its run directory still have to
        // work: temporary files, caches, and the logs the harness collects.
        for root in writableRoots {
            lines.append("(allow file-write* (subpath \(quote(root))))")
        }
        // Last, so nothing above re-opens them.
        for path in deniedWritePaths {
            for spelling in spellings(of: path) {
                lines.append("(deny file-write* (subpath \(quote(spelling))))")
            }
        }
        lines.append("(allow file-write* (subpath \(quote(workspaceURL.path))))")
        for spelling in spellings(of: workspaceURL) {
            lines.append("(allow file-write* (subpath \(quote(spelling))))")
        }

        // Execution last, and as an allowlist. Refusing every binary outside
        // the toolchain is what stops the agent routing around a denied
        // wrapper: copying it, downloading another, or writing its own.
        if !executableRoots.isEmpty {
            lines.append("(deny process-exec*)")
            for root in executableRoots {
                // Same resolved-path problem as the read rules: an allowance
                // written against /tmp matches nothing, and here that stops
                // the agent running itself rather than letting something
                // through.
                for spelling in spellings(of: root) {
                    lines.append("(allow process-exec (subpath \(quote(spelling))))")
                }
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

    /// Places outside the workspace an agent legitimately writes to.
    ///
    /// Its hermetic HOME, the temporary directory it and the toolchain use,
    /// and `/dev` for the null device. Without these the agent cannot start,
    /// and a build cannot write an intermediate.
    var writableRoots: [String] {
        var roots = ["/dev", "/private/tmp", "/tmp", "/private/var/folders", "/var/folders"]
        if let home = ProcessInfo.processInfo.environment["HOME"], home.hasPrefix("/") {
            roots.append(home)
        }
        if let tmp = ProcessInfo.processInfo.environment["TMPDIR"], tmp.hasPrefix("/") {
            roots.append(tmp)
        }
        return roots
    }

    /// Every spelling of a path a rule has to name.
    ///
    /// The sandbox matches paths after the kernel has resolved them, so a rule
    /// written against a symlinked path matches nothing. On macOS that is not
    /// an edge case: `/tmp` and `/var` are symlinks into `/private`, so a rule
    /// naming either is denied on paper and readable in fact. Both spellings
    /// are emitted, because the unresolved one is what a reader of the profile
    /// recognises and the resolved one is what the kernel enforces.
    private func spellings(of path: URL) -> [String] {
        let resolved = Self.realPath(of: path)
        return resolved == path.path ? [path.path] : [path.path, resolved]
    }

    /// A path with every symlink resolved, including ones Foundation leaves
    /// alone.
    ///
    /// `URL.resolvingSymlinksInPath()` returns `/var/folders/…` unchanged even
    /// though the real directory is `/private/var/folders/…`, which is exactly
    /// the case a sandbox rule must not get wrong. `realpath(3)` needs the
    /// path to exist, so the longest existing ancestor is resolved and the
    /// rest appended: a rule written before its directory is created still
    /// names the right place.
    static func realPath(of path: URL) -> String {
        var trailing: [String] = []
        var current = path.standardizedFileURL
        while current.path != "/" && !current.path.isEmpty {
            if let resolved = resolve(current.path) {
                return ([resolved.hasSuffix("/") ? String(resolved.dropLast()) : resolved]
                    + trailing.reversed()).joined(separator: "/")
            }
            trailing.append(current.lastPathComponent)
            current = current.deletingLastPathComponent()
        }
        return path.path
    }

    private static func resolve(_ path: String) -> String? {
        guard let buffer = realpath(path, nil) else { return nil }
        defer { free(buffer) }
        return String(cString: buffer)
    }

    /// SBPL string literal. A path with a quote in it would otherwise end the
    /// literal early and change what the rule denies.
    private func quote(_ path: String) -> String {
        "\"" + path.replacingOccurrences(of: "\\", with: "\\\\")
                   .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
