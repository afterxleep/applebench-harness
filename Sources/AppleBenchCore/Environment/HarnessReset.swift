import Foundation

/// Removes only repository-local state that AppleBench can recreate.
public struct HarnessReset: Sendable {
    public let rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
    }

    public static let generatedPaths = [
        ".applebench",
        ".build",
        ".jekyll-cache",
        "site/.jekyll-cache",
        "site/_site",
    ]

    /// Returns the relative paths that existed and were removed.
    @discardableResult
    public func run() throws -> [String] {
        var removed: [String] = []
        for path in Self.generatedPaths {
            let target = rootURL.appendingPathComponent(path).standardizedFileURL
            guard target.path.hasPrefix(rootURL.path + "/") else {
                throw CocoaError(.fileWriteInvalidFileName)
            }
            guard FileManager.default.fileExists(atPath: target.path) else { continue }
            try FileManager.default.removeItem(at: target)
            removed.append(path)
        }
        return removed
    }
}
