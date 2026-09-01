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
            // When `glob` is on, locate every workspace file whose
            // relative path matches the pattern. The assertion is
            // satisfied if at least one match is found, and the
            // content/size/JSON checks run against the first match.
            // Otherwise the path is treated as a literal workspace-
            // relative path, and the file must lie inside the
            // workspace (paths that escape via `..` are rejected as
            // an invalid task — see the existing escape check below).
            let resolvedURL: URL
            let resolvedPath: String
            let isGlob = assertion.glob == true
            if isGlob {
                let matches = Self.globMatches(assertion.path, in: context.workspaceURL)
                guard let first = matches.first else {
                    if let expectedExistence = assertion.exists, expectedExistence {
                        failures.append("\(assertion.path): no workspace file matched the glob")
                    }
                    continue
                }
                resolvedURL = first
                resolvedPath = assertion.path
            } else {
                let fileURL = context.workspaceURL.appendingPathComponent(assertion.path)
                let workspacePath = context.workspaceURL.standardizedFileURL.path
                let candidatePath = fileURL.standardizedFileURL.path
                guard candidatePath == workspacePath || candidatePath.hasPrefix(workspacePath + "/") else {
                    throw BenchmarkFailure.invalidTask("File assertion path escapes the workspace: \(assertion.path)")
                }
                resolvedURL = fileURL
                resolvedPath = assertion.path
            }
            let exists = FileManager.default.fileExists(atPath: resolvedURL.path)

            if let expectedExistence = assertion.exists, exists != expectedExistence {
                failures.append("\(resolvedPath): expected to \(expectedExistence ? "exist" : "not exist")")
                continue
            }

            if assertion.contains != nil || assertion.matches != nil {
                guard exists, let contents = try? String(contentsOf: resolvedURL, encoding: .utf8) else {
                    failures.append("\(resolvedPath): unreadable or missing")
                    continue
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
                    continue
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
                    continue
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
                    continue
                }
                // The eight-byte signature every PNG opens with. Checked as
                // bytes: `contains` and `matches` read the file as UTF-8, and
                // a real image is not valid UTF-8, so they can only ever
                // report an image as unreadable.
                let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
                guard data.count >= signature.count, Array(data.prefix(signature.count)) == signature else {
                    failures.append("\(resolvedPath): is not a PNG")
                    continue
                }
            }
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

    /// Walks the workspace and returns every file whose path relative
    /// to the workspace matches a simple `*` / `**` glob. The
    /// implementation is deliberately limited:
    ///
    /// - `**` matches zero or more path segments (including `/`)
    /// - `*`  matches a single path segment (no `/`)
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
                let relPath = entry.path.replacingOccurrences(of: workspace.path + "/", with: "")

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
            } else {
                if q.isEmpty { return false }
                if seg != q.removeFirst() { return false }
            }
        }
        return q.isEmpty
    }
}
