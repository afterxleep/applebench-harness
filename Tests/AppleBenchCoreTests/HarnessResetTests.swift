import Foundation
import Testing
@testable import AppleBenchCore

@Suite("Harness reset")
struct HarnessResetTests {
    @Test("Removes generated state and preserves repository artifacts")
    func removesOnlyGeneratedState() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("applebench-reset-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let generated = [
            ".applebench/runs/old/result.json",
            ".applebench/taskset/.git/HEAD",
            ".build/cache.db",
            ".jekyll-cache/cache",
            "site/.jekyll-cache/cache",
            "site/_site/index.html",
        ]
        for path in generated {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "generated".write(to: url, atomically: true, encoding: .utf8)
        }
        let preserved = ["Reports/report.json", "Data/model-catalog.json", "site/_config.yml"]
        for path in preserved {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "owned".write(to: url, atomically: true, encoding: .utf8)
        }

        let removed = try HarnessReset(rootURL: root).run()

        #expect(Set(removed) == Set([".applebench", ".build", ".jekyll-cache", "site/.jekyll-cache", "site/_site"]))
        for path in generated {
            #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path))
        }
        for path in preserved {
            #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path))
        }
    }
}
