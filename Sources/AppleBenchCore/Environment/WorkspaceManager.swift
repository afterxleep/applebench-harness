import Foundation

/// Creates and manages the isolated workspace for one run.
///
/// Every run gets a fresh clone at the exact task commit; grading never
/// happens against a dirty checkout from another run. The workspace lives
/// beneath the run directory, which itself is confined to the AppleBench runs
/// root.
public struct WorkspaceManager: Sendable {
    public struct Workspace: Sendable {
        public var workspaceURL: URL
        /// The resolved SHA actually checked out.
        public var baseCommit: String
    }

    public struct DiffSummary: Sendable, Equatable {
        public var patch: String
        public var changedFiles: [String]
        public var filesChanged: Int
        public var insertions: Int
        public var deletions: Int
        /// A commit created by the agent, if HEAD moved.
        public var finalCommit: String?
    }

    private let processRunner: any ProcessRunning
    /// Generous fixed timeout for git operations; clones of benchmark
    /// repositories should be far faster than this.
    private let gitTimeout: Duration = .seconds(600)

    public init(processRunner: any ProcessRunning = ProcessRunner()) {
        self.processRunner = processRunner
    }

    /// Clones `repository` into `<runDirectory>/workspace` and checks out the
    /// exact commit, verifying the resulting state is clean.
    public func prepareWorkspace(
        repository: RepositorySpecification,
        runDirectoryURL: URL
    ) async throws -> Workspace {
        let workspaceURL = runDirectoryURL.appendingPathComponent("workspace", isDirectory: true)

        let cloneSource = resolveCloneSource(repository.url)
        try await git(["clone", cloneSource, workspaceURL.path], in: nil, describe: "clone \(repository.url)")

        if repository.commit.uppercased() != "HEAD" {
            try await git(["checkout", "--detach", repository.commit], in: workspaceURL, describe: "checkout \(repository.commit)")
        }

        let status = try await git(["status", "--porcelain"], in: workspaceURL, describe: "status")
        guard status.isEmpty else {
            throw BenchmarkFailure.repositoryFailure(
                "Checkout of \(repository.commit) is not clean:\n\(status)"
            )
        }

        let baseCommit = try await git(["rev-parse", "HEAD"], in: workspaceURL, describe: "rev-parse HEAD")
        return Workspace(workspaceURL: workspaceURL, baseCommit: baseCommit)
    }

    /// Captures the complete diff the agent produced relative to the base
    /// commit, including untracked files (via a temporary index add), and
    /// writes it to `diff.patch` in the run directory.
    public func captureDiff(
        workspace: Workspace,
        runDirectoryURL: URL
    ) async throws -> DiffSummary {
        let workspaceURL = workspace.workspaceURL

        // Stage everything (including untracked files) in the index only, so
        // `git diff --cached` reflects the agent's full footprint. The
        // workspace is discarded or archived afterwards, so mutating the
        // index is safe.
        try await git(["add", "-A"], in: workspaceURL, describe: "add -A")

        let head = try await git(["rev-parse", "HEAD"], in: workspaceURL, describe: "rev-parse HEAD")
        let finalCommit = head == workspace.baseCommit ? nil : head

        let patch = try await git(
            ["diff", "--cached", "--binary", workspace.baseCommit],
            in: workspaceURL,
            describe: "diff"
        )
        let stat = try await git(
            ["diff", "--cached", "--numstat", workspace.baseCommit],
            in: workspaceURL,
            describe: "diff --numstat"
        )

        var changedFiles: [String] = []
        var insertions = 0
        var deletions = 0
        for line in stat.split(separator: "\n") {
            let columns = line.split(separator: "\t", maxSplits: 2)
            guard columns.count == 3 else { continue }
            insertions += Int(columns[0]) ?? 0
            deletions += Int(columns[1]) ?? 0
            changedFiles.append(String(columns[2]))
        }

        let patchURL = runDirectoryURL.appendingPathComponent("diff.patch")
        try patch.write(to: patchURL, atomically: true, encoding: .utf8)

        return DiffSummary(
            patch: patch,
            changedFiles: changedFiles,
            filesChanged: changedFiles.count,
            insertions: insertions,
            deletions: deletions,
            finalCommit: finalCommit
        )
    }

    public func removeWorkspace(_ workspace: Workspace) {
        try? FileManager.default.removeItem(at: workspace.workspaceURL)
    }

    /// Local paths are cloned as filesystem remotes; anything else is passed
    /// to git verbatim.
    private func resolveCloneSource(_ url: String) -> String {
        if url.hasPrefix("/") || url.hasPrefix("./") || url.hasPrefix("../") || url.hasPrefix("~") {
            return (url as NSString).expandingTildeInPath
        }
        return url
    }

    @discardableResult
    private func git(
        _ arguments: [String],
        in workingDirectory: URL?,
        describe description: String
    ) async throws -> String {
        let result: ProcessExecutionResult
        do {
            result = try await processRunner.run(
                ProcessCommand(
                    executable: "/usr/bin/git",
                    arguments: arguments,
                    workingDirectory: workingDirectory
                ),
                timeout: gitTimeout,
                outputHandler: nil
            )
        } catch {
            throw BenchmarkFailure.repositoryFailure("git \(description): \(error)")
        }
        guard result.exitCode == 0 else {
            throw BenchmarkFailure.repositoryFailure(
                "git \(description) failed (exit \(result.exitCode.map(String.init) ?? "signal")): \(result.standardError.trimmingCharacters(in: .whitespacesAndNewlines))"
            )
        }
        return result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Lays out and confines run directories beneath the AppleBench root.
public struct RunDirectoryLayout: Sendable {
    public let rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    public static func `default`(under baseDirectory: URL) -> RunDirectoryLayout {
        RunDirectoryLayout(rootURL: baseDirectory.appendingPathComponent(".applebench/runs", isDirectory: true))
    }

    /// Creates `<root>/<timestamp>-<task>-<agent>/` with `logs/` inside.
    public func createRunDirectory(taskID: String, agentID: String, date: Date = Date()) throws -> (runID: String, url: URL) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HHmmss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")

        // Sanitize path components defensively; task ids are already
        // restricted by validation, agent ids come from the registry.
        let safeTask = sanitize(taskID)
        let safeAgent = sanitize(agentID)
        let runID = "\(formatter.string(from: date))-\(safeTask)-\(safeAgent)"

        // Resolve the root once and build the run directory from it, so both
        // sides of the containment check are in the same form. On macOS `/tmp`
        // is a symlink to `/private/tmp`, and `resolvingSymlinksInPath` only
        // rewrites components that exist — so resolving the root and the
        // not-yet-created run directory separately gives two different answers
        // and the check rejects the harness's own directory.
        let resolvedRoot = rootURL.resolvingSymlinksInPath().standardizedFileURL
        let runURL = resolvedRoot.appendingPathComponent(runID, isDirectory: true)
        // The trailing separator keeps `/runs` from appearing to contain
        // `/runs-elsewhere`.
        let boundary = resolvedRoot.path.hasSuffix("/") ? resolvedRoot.path : resolvedRoot.path + "/"
        guard runURL.standardizedFileURL.path.hasPrefix(boundary) else {
            throw BenchmarkFailure.infrastructureFailure(
                "Run directory escapes the runs root: \(runURL.path) is not inside \(rootURL.path)"
            )
        }
        // A run id is a UTC timestamp to the second plus the task and agent,
        // and two benchmark processes comparing different models use the same
        // agent on the same tasks. Starting the same task in the same second is
        // therefore not far-fetched, and `withIntermediateDirectories` does not
        // complain about an existing directory — the second run would quietly
        // overwrite the first's result.json and events.jsonl. Claim the
        // directory exclusively instead, and take a suffix when it is taken.
        var uniqueID = runID
        var uniqueURL = runURL
        var attempt = 2
        while true {
            do {
                try FileManager.default.createDirectory(
                    at: uniqueURL,
                    withIntermediateDirectories: false
                )
                break
            } catch let error as NSError where error.code == NSFileWriteFileExistsError {
                guard attempt <= 50 else {
                    throw BenchmarkFailure.infrastructureFailure(
                        "Could not find a free run directory beside \(runURL.path)"
                    )
                }
                uniqueID = "\(runID)-\(attempt)"
                uniqueURL = resolvedRoot.appendingPathComponent(uniqueID, isDirectory: true)
                attempt += 1
            }
        }
        try FileManager.default.createDirectory(
            at: uniqueURL.appendingPathComponent("logs", isDirectory: true),
            withIntermediateDirectories: true
        )
        return (uniqueID, uniqueURL)
    }

    private func sanitize(_ component: String) -> String {
        String(component.map { character in
            character.isLetter || character.isNumber || character == "-" || character == "_" ? character : "-"
        })
    }
}
