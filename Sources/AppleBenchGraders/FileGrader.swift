import AppleBenchCore
import Foundation

/// Deterministic assertions about the final workspace: file existence,
/// contents, regex matches, and whether the run diff touched a path.
/// Intentionally simple.
public struct FileGrader: Grader {
    public let identifier = "file"
    private let configuration: FileGraderConfiguration

    public init(configuration: FileGraderConfiguration) {
        self.configuration = configuration
    }

    public func grade(task: BenchmarkTask, context: GradingContext) async throws -> GradingResult {
        let start = ContinuousClock.now
        var failures: [String] = []

        for assertion in configuration.assertions {
            if assertion.glob == true {
                failures += Self.globFailures(for: assertion, context: context)
                continue
            }
            let fileURL = context.workspaceURL.appendingPathComponent(assertion.path)
            let workspacePath = context.workspaceURL.standardizedFileURL.path
            let candidatePath = fileURL.standardizedFileURL.path
            guard candidatePath == workspacePath || candidatePath.hasPrefix(workspacePath + "/") else {
                throw BenchmarkFailure.invalidTask("File assertion path escapes the workspace: \(assertion.path)")
            }
            failures += try Self.failures(
                of: assertion, at: fileURL, relativePath: assertion.path, context: context
            )
        }

        let passed = failures.isEmpty
        return GradingResult(
            grader: identifier,
            passed: passed,
            duration: start.duration(to: .now),
            summary: passed
                ? "\(configuration.assertions.count) file assertion(s) satisfied"
                : failures.joined(separator: "; ")
        )
    }

    /// A glob assertion holds when at least one matching file satisfies every
    /// check it makes.
    ///
    /// Judging only the first match made the verdict depend on directory
    /// order: a test file the agent added passed or failed according to where
    /// it happened to list beside the fixture's own.
    static func globFailures(for assertion: FileAssertion, context: GradingContext) -> [String] {
        let matches = globMatches(assertion.path, in: context.workspaceURL)
        let checksFiles = assertion.contains != nil || assertion.matches != nil
            || assertion.minSize != nil || assertion.isJSON == true || assertion.isPNG == true
        guard !matches.isEmpty else {
            if assertion.exists == true || checksFiles {
                return ["\(assertion.path): no workspace file matched the glob"]
            }
            return []
        }
        var firstFailures: [String]?
        for match in matches {
            let relative = relativePath(of: match, in: context.workspaceURL)
            let failures = (try? Self.failures(of: assertion, at: match, relativePath: relative, context: context))
                ?? ["\(relative): could not be checked"]
            if failures.isEmpty { return [] }
            if firstFailures == nil { firstFailures = failures }
        }
        return firstFailures ?? []
    }

    static func failures(
        of assertion: FileAssertion,
        at resolvedURL: URL,
        relativePath resolvedPath: String,
        context: GradingContext
    ) throws -> [String] {
        var failures: [String] = []
        let exists = FileManager.default.fileExists(atPath: resolvedURL.path)

        if let expectedExistence = assertion.exists, exists != expectedExistence {
            failures.append("\(resolvedPath): expected to \(expectedExistence ? "exist" : "not exist")")
            return failures
        }

        if assertion.contains != nil || assertion.matches != nil {
            guard exists, let contents = try? String(contentsOf: resolvedURL, encoding: .utf8) else {
                failures.append("\(resolvedPath): unreadable or missing")
                return failures
            }
            if let needle = assertion.contains, !contents.contains(needle) {
                failures.append("\(resolvedPath): does not contain expected text")
            }
            if let pattern = assertion.matches {
                guard let regex = try? NSRegularExpression(pattern: pattern) else {
                    throw BenchmarkFailure.invalidTask("Invalid regex in file assertion: \(pattern)")
                }
                let range = NSRange(contents.startIndex..., in: contents)
                if regex.firstMatch(in: contents, range: range) == nil {
                    failures.append("\(resolvedPath): does not match /\(pattern)/")
                }
            }
        }

        if let changed = assertion.changed {
            let wasChanged = context.changedFiles.contains(resolvedPath)
            if wasChanged != changed {
                failures.append("\(resolvedPath): expected diff to \(changed ? "include" : "exclude") this path")
            }
        }

        if let minSize = assertion.minSize {
            guard exists else {
                failures.append("\(resolvedPath): missing, cannot check size")
                return failures
            }
            let attrs = try? FileManager.default.attributesOfItem(atPath: resolvedURL.path)
            let actualSize = (attrs?[.size] as? Int) ?? 0
            if actualSize < minSize {
                failures.append("\(resolvedPath): \(actualSize) bytes, expected at least \(minSize)")
            }
        }

        if assertion.isJSON == true {
            guard exists, let data = try? Data(contentsOf: resolvedURL) else {
                failures.append("\(resolvedPath): unreadable or missing, cannot check JSON")
                return failures
            }
            // JSONSerialization is a real parse — `JSONDecoder` would
            // also work but requires a Decodable type. Either catches
            // a non-JSON payload.
            if (try? JSONSerialization.jsonObject(with: data)) == nil {
                failures.append("\(resolvedPath): is not valid JSON")
            }
        }

        if assertion.isPNG == true {
            guard exists, let data = try? Data(contentsOf: resolvedURL) else {
                failures.append("\(resolvedPath): unreadable or missing, cannot check PNG")
                return failures
            }
            // The eight-byte signature every PNG opens with. Checked as
            // bytes: `contains` and `matches` read the file as UTF-8, and
            // a real image is not valid UTF-8, so they can only ever
            // report an image as unreadable.
            let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
            guard data.count >= signature.count, Array(data.prefix(signature.count)) == signature else {
                failures.append("\(resolvedPath): is not a PNG")
                return failures
            }
        }
        return failures
    }

    /// Walks the workspace and returns every file whose path relative
    /// to the workspace matches a simple `*` / `**` glob. The
    /// implementation is deliberately limited:
    ///
    /// - `**` matches zero or more path segments (including `/`)
    /// - `*`  matches a single path segment (no `/`)
    /// - a segment containing `*`, such as `*.swift`, matches one segment by wildcard
    /// - everything else is treated as a literal segment
    ///
    /// This is enough for the "this artifact must exist somewhere in
    /// the workspace" use case without pulling in a full glob
    /// implementation.
    static func globMatches(_ pattern: String, in workspace: URL) -> [URL] {
        let fm = FileManager.default
        var results: [URL] = []

        func walk(_ dir: URL, segments: [String]) {
            // Match the pattern tail against the directory contents.
            // A path can be matched multiple ways; we collect all.
            let entries = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
            for entry in entries {
                let name = entry.lastPathComponent
                // Skip the parts of the workspace we never care about
                // for a "did the agent produce this artifact" check.
                if name == ".git" || name == ".applebench" || name == "DerivedData" {
                    continue
                }
                if isHidden(name) { continue }
                let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                let relPath = relativePath(of: entry, in: workspace)

                if matchSegments(pattern: segments, against: relPath.split(separator: "/").map(String.init)) {
                    results.append(entry)
                }
                if isDirectory {
                    walk(entry, segments: segments)
                }
            }
        }

        walk(workspace, segments: pattern.split(separator: "/").map(String.init))
        return results
    }

    /// A path relative to the workspace, comparing resolved paths: a
    /// workspace under `/var` lists its files under `/private/var`, and a
    /// plain prefix strip then leaves them absolute and matching nothing.
    static func relativePath(of url: URL, in workspace: URL) -> String {
        let root = workspace.resolvingSymlinksInPath().standardizedFileURL.path
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        return path.hasPrefix(root + "/") ? String(path.dropFirst(root.count + 1)) : path
    }

    private static func isHidden(_ name: String) -> Bool {
        name.hasPrefix(".")
    }

    /// Recursive glob matcher for the `*` / `**` subset. A `**`
    /// segment matches zero or more directory levels, so
    /// `**/build-settings.json` matches `build-settings.json` and
    /// `build/build-settings.json` and `a/b/build-settings.json`.
    private static func matchSegments(pattern: [String], against path: [String]) -> Bool {
        var p = pattern
        var q = path
        while !p.isEmpty {
            let seg = p.removeFirst()
            if seg == "**" {
                // `**` consumes the rest of the pattern. Try every
                // suffix of the path tail.
                if p.isEmpty { return true }
                for i in 0...q.count {
                    if matchSegments(pattern: p, against: Array(q.dropFirst(i))) {
                        return true
                    }
                }
                return false
            } else if seg == "*" {
                // `*` consumes exactly one path segment.
                if q.isEmpty { return false }
                q.removeFirst()
            } else if seg.contains("*") {
                // A wildcard inside one segment, such as `*.swift`.
                if q.isEmpty { return false }
                if fnmatch(seg, q.removeFirst(), 0) != 0 { return false }
            } else {
                if q.isEmpty { return false }
                if seg != q.removeFirst() { return false }
            }
        }
        return q.isEmpty
    }
}
