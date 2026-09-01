import Foundation

/// Puts a fixture's graded tests into the workspace, after the agent has gone.
///
/// A benchmark that ships its assertions to the agent is measuring reading
/// comprehension. `prepare-fixtures.sh` keeps each fixture's `Verification/`
/// directory — its graded tests and the project that builds them — outside
/// every checkout, under `.applebench/verification/<Fixture>/`. The agent
/// therefore receives an app with no test target: no assertions, no test file
/// names, no test class names, nothing that describes how it will be judged.
///
/// This overlays that directory onto the workspace between the diff capture
/// and the first grader. The ordering matters: the diff is already recorded,
/// so nothing here is ever attributed to the agent, and the agent's process
/// has already exited, so nothing here was ever visible to it.
///
/// Fixtures whose planted defect lives in the project configuration do not
/// have a `Verification/` directory. Overlaying a pre-generated project onto
/// those would discard the very change the task asks for, so they keep their
/// tests in the checkout and are graded on the built product instead.
public struct VerificationMaterialiser: Sendable {
    /// Directory holding `<Fixture>/` overlays. Defaults to
    /// `.applebench/verification` beneath the current working directory,
    /// matching where `prepare-fixtures.sh` writes them.
    private let verificationDirectory: URL

    public init(verificationDirectory: URL? = nil) {
        self.verificationDirectory = verificationDirectory
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".applebench/verification", isDirectory: true)
    }

    /// What was overlaid, for the run's event log.
    public struct Outcome: Sendable, Equatable {
        public var fixture: String
        /// Workspace-relative paths written. Empty when the fixture has no
        /// verification bundle, which is not an error.
        public var paths: [String]

        public var isEmpty: Bool { paths.isEmpty }
    }

    @discardableResult
    public func materialise(
        fixture: String,
        into workspaceURL: URL,
        processRunner: (any ProcessRunning)? = nil
    ) async throws -> Outcome {
        let source = verificationDirectory.appendingPathComponent(fixture, isDirectory: true)

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: source.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return Outcome(fixture: fixture, paths: [])
        }

        var written: [String] = []
        for entry in try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
            let destination = workspaceURL.appendingPathComponent(entry.lastPathComponent)
            // Overlay semantics: a bundle entry replaces whatever the agent
            // left at that path. An agent that wrote its own `Tests/` is not
            // penalised — its work is in the captured diff — but it does not
            // get to decide what the graded assertions are.
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: entry, to: destination)
            written.append(entry.lastPathComponent)
        }

        // The bundle carries the fixture's real spec as well as the tests. The
        // project is rebuilt from it rather than restored from a snapshot,
        // because the spec lists source *directories*: regenerating picks up
        // files the agent added, where a pre-generated project would silently
        // drop them. The pre-generated project travels with the bundle as the
        // fallback for a host without XcodeGen.
        let spec = workspaceURL.appendingPathComponent("project.yml")
        if FileManager.default.fileExists(atPath: spec.path) {
            if let processRunner {
                let result = try? await processRunner.run(
                    ProcessCommand(
                        executable: "xcodegen",
                        arguments: ["generate", "--quiet", "--spec", "project.yml"],
                        workingDirectory: workspaceURL
                    ),
                    timeout: .seconds(120)
                )
                if result?.exitCode != 0 {
                    throw BenchmarkFailure.graderFailure(
                        grader: "verification",
                        message: "Could not regenerate \(fixture)'s project from its spec at grading time. "
                            + "XcodeGen is required to grade an isolated fixture."
                    )
                }
            }
            try? FileManager.default.removeItem(at: spec)
            written.removeAll { $0 == "project.yml" }
        }

        return Outcome(fixture: fixture, paths: written.sorted())
    }

    /// The fixture a task draws its workspace from.
    public static func fixtureName(for task: BenchmarkTask) -> String {
        var url = task.repository.url
        while url.hasSuffix("/") { url.removeLast() }
        let name = (url as NSString).lastPathComponent
        return name.hasSuffix(".git") ? String(name.dropLast(4)) : name
    }
}
