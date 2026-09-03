import Foundation

/// Everything an agent adapter needs to execute one benchmark run.
///
/// Deliberately excludes grader configuration: adapters receive the task
/// prompt and workspace, never the evaluation criteria.
public struct RunContext: Sendable {
    public let runID: String
    /// The isolated git checkout the agent works in.
    public let workspaceURL: URL
    /// The run's private directory (events, results, logs) — outside the workspace.
    public let runDirectoryURL: URL
    public let logsDirectoryURL: URL
    /// Model override requested on the command line, if any.
    public let model: String?
    /// Reasoning effort requested on the command line, if any.
    public let effort: String?
    /// Environment variables explicitly allowlisted for the agent process.
    /// Adapters must not leak the full parent environment beyond this set plus
    /// what they minimally require (e.g. `PATH`, `HOME`).
    public let environmentAllowlist: [String]
    /// When true, the agent's `PATH` is filtered to remove well-known
    /// Apple-toolchain wrapper CLIs. Set by the calibration runs; off
    /// by default.
    public let stripWrapperCLIs: Bool
    /// Seals the agent away from the paths that hold the answers. `nil` leaves
    /// them readable, which is only appropriate for a local run nobody is
    /// scoring.
    public let sandbox: AgentSandbox?
    public let limits: RunLimits
    public let environment: EnvironmentSnapshot

    public init(
        runID: String,
        workspaceURL: URL,
        runDirectoryURL: URL,
        logsDirectoryURL: URL,
        model: String?,
        effort: String? = nil,
        environmentAllowlist: [String] = [],
        stripWrapperCLIs: Bool = false,
        sandbox: AgentSandbox? = nil,
        limits: RunLimits,
        environment: EnvironmentSnapshot
    ) {
        self.runID = runID
        self.workspaceURL = workspaceURL
        self.runDirectoryURL = runDirectoryURL
        self.logsDirectoryURL = logsDirectoryURL
        self.model = model
        self.effort = effort
        self.environmentAllowlist = environmentAllowlist
        self.stripWrapperCLIs = stripWrapperCLIs
        self.sandbox = sandbox
        self.limits = limits
        self.environment = environment
    }

    /// Builds the child environment for an agent process: a minimal base plus
    /// explicitly allowlisted variables from the parent environment.
    ///
    /// When `stripWrapperCLIs` is true, well-known third-party wrapper
    /// CLIs that wrap Apple's toolchain (FlowDeck, Tuist, xcbeautify,
    /// fastlane, ...) are stripped from the agent's `PATH`. This is
    /// opt-in: the calibration runs use it, day-to-day runs don't. A
    /// model that solves a task by typing `flowdeck build` is solving
    /// the wrong task — the harness should measure raw-toolchain skill,
    /// not wrapper-recall. But a real agent should be free to use the
    /// wrapper when the run is asking the model to do the work, not to
    /// prove it can do the work without one.
    ///
    /// When `hermeticHome` is true, the agent's `HOME` is redirected to
    /// a fresh temp directory. The agent can still authenticate via
    /// env vars (`ANTHROPIC_API_KEY`, `OPENROUTER_API_KEY`, …) which
    /// are passed through, but it has no access to the host's
    /// `~/.claude/skills/`, `~/.config/opencode/skills/`, or any other
    /// user-installed skill. Skills are an attack surface on the
    /// calibration — a model that auto-loads the FlowDeck skill can
    /// solve "use raw xcodebuild" tasks via the wrapper without the
    /// harness noticing. The hermetic HOME prevents that.
    public func agentEnvironment(
        extra: [String: String] = [:],
        stripWrapperCLIs: Bool = false,
        hermeticHome: URL? = nil
    ) -> [String: String] {
        let parent = ProcessInfo.processInfo.environment
        var environment: [String: String] = [:]
        for key in ["USER", "TMPDIR", "SHELL", "TERM", "LANG", "LC_ALL"] {
            environment[key] = parent[key]
        }
        if let hermeticHome {
            environment["HOME"] = hermeticHome.path
            environment["XDG_CONFIG_HOME"] = hermeticHome.appendingPathComponent(".config").path
            environment["XDG_CACHE_HOME"] = hermeticHome.appendingPathComponent(".cache").path
            environment["XDG_DATA_HOME"] = hermeticHome.appendingPathComponent(".local/share").path
        } else {
            environment["HOME"] = parent["HOME"]
        }
        for key in environmentAllowlist {
            environment[key] = parent[key]
        }
        for (key, value) in extra {
            environment[key] = value
        }
        if let path = environment["PATH"] ?? parent["PATH"] {
            if stripWrapperCLIs {
                environment["PATH"] = Self.filterWrapperCLIs(
                    from: path,
                    agentBinaryNames: ["claude", "opencode", "claude-code", "codex"]
                )
            } else {
                environment["PATH"] = path
            }
        }
        return environment.compactMapValues { $0 }
    }

    /// Removes any PATH directory that contains a known third-party Apple
    /// wrapper CLI. This is a coarse allowlist, not a security boundary —
    /// the agent could still invoke a wrapper by absolute path — but it
    /// keeps the "easy" tool off the search path so the calibration
    /// measures raw-toolchain skill, not wrapper-recall.
    ///
    /// The directory that contains the agent's harness binary (claude,
    /// opencode, …) is preserved even if it also contains a wrapper,
    /// because filtering that directory out would make the harness
    /// itself unreachable to the agent subprocess.
    public static func filterWrapperCLIs(
        from path: String,
        agentBinaryNames: [String] = []
    ) -> String {
        let wrapperNames: Set<String> = [
            "flowdeck", "tuist", "xcbeautify", "xcbeautify-tests",
            "fastlane", "swift-package-bundler", "periphery", "swiftlint",
            "xcodegen",
        ]
        let directories = path.split(separator: ":").map(String.init)
        let fm = FileManager.default
        // Pre-compute the directories the agent's binaries live in. If a
        // directory contains BOTH a wrapper AND a harness binary, the
        // harness binary wins.
        var preservedDirs: Set<String> = []
        for name in agentBinaryNames {
            for directory in directories {
                if fm.isExecutableFile(atPath: "\(directory)/\(name)") {
                    preservedDirs.insert(directory)
                }
            }
        }
        let filtered = directories.filter { directory in
            if preservedDirs.contains(directory) { return true }
            return !wrapperNames.contains { wrapper in
                fm.isExecutableFile(atPath: "\(directory)/\(wrapper)")
            }
        }
        return filtered.joined(separator: ":")
    }

    /// Builds a sanitized PATH that hides the agent's harness directory
    /// entirely, then re-exposes the harness binary via a temporary
    /// symlink. Use this when the host's `claude` (or `opencode`) shares
    /// its directory with one of the wrapper CLIs and the filter would
    /// otherwise either drop the agent's binary or leave the wrapper
    /// reachable through the same dir.
    ///
    /// Returns the sanitized PATH string and the temporary directory
    /// that holds the harness symlink. The caller is responsible for
    /// keeping the directory alive for the duration of the agent run
    /// and removing it afterwards.
    public static func sanitizedPath(
        forAgentBinary agentBinary: String,
        in harnessPath: String
    ) throws -> (path: String, tempDir: URL) {
        let wrapperNames: Set<String> = [
            "flowdeck", "tuist", "xcbeautify", "xcbeautify-tests",
            "fastlane", "swift-package-bundler", "periphery", "swiftlint",
            "xcodegen",
        ]
        let directories = harnessPath.split(separator: ":").map(String.init)
        let fm = FileManager.default

        // Locate the agent binary and copy it into a clean temp dir
        // (symlink) so we can scrub the original directory from PATH
        // without losing the binary.
        var sourcePath: String?
        for directory in directories {
            let candidate = "\(directory)/\(agentBinary)"
            if fm.isExecutableFile(atPath: candidate) {
                sourcePath = candidate
                break
            }
        }
        guard let source = sourcePath else {
            throw BenchmarkFailure.agentLaunchFailure(
                "Agent binary '\(agentBinary)' not found on PATH. Install it or adjust PATH before running."
            )
        }

        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("applebench-sanitized-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let symlinkPath = tempDir.appendingPathComponent(agentBinary).path
        try fm.createSymbolicLink(atPath: symlinkPath, withDestinationPath: source)

        // Build a new PATH: the temp dir first, then every original
        // directory that does not contain a wrapper. This guarantees
        // the agent's binary is found before any wrapper, and the
        // wrappers are no longer in the search path.
        var cleanDirs: [String] = []
        for directory in directories {
            if directory == tempDir.path { continue }
            if wrapperNames.contains(where: {
                fm.isExecutableFile(atPath: "\(directory)/\($0)")
            }) { continue }
            cleanDirs.append(directory)
        }
        return ("\(tempDir.path):\(cleanDirs.joined(separator: ":"))", tempDir)
    }
}
