import AppleBenchCore
import Foundation
import Testing
@testable import AppleBenchGraders

@Suite("Xcodeproj grader")
struct XcodeprojGraderTests {

    // MARK: - Assertion evaluation

    @Test("equals compares the resolved value exactly")
    func equals() {
        #expect(XcodeprojGrader.evaluate(
            value: "18.0", equals: "18.0", matches: nil, exists: nil, describe: "s"
        ) == nil)

        let failure = XcodeprojGrader.evaluate(
            value: "26.0", equals: "18.0", matches: nil, exists: nil, describe: "build setting X"
        )
        #expect(failure == "build setting X is '26.0', expected '18.0'")
    }

    @Test("matches applies a regular expression")
    func matches() {
        #expect(XcodeprojGrader.evaluate(
            value: "6.0", equals: nil, matches: "^6", exists: nil, describe: "s"
        ) == nil)
        #expect(XcodeprojGrader.evaluate(
            value: "5.0", equals: nil, matches: "^6", exists: nil, describe: "s"
        ) != nil)
    }

    @Test("An invalid regular expression fails the assertion rather than crashing")
    func invalidExpression() {
        let failure = XcodeprojGrader.evaluate(
            value: "6.0", equals: nil, matches: "([", exists: nil, describe: "s"
        )
        #expect(failure?.contains("invalid regular expression") == true)
    }

    @Test("exists distinguishes unset from set")
    func exists() {
        #expect(XcodeprojGrader.evaluate(
            value: nil, equals: nil, matches: nil, exists: true, describe: "key K"
        ) == "key K is not set")
        #expect(XcodeprojGrader.evaluate(
            value: "x", equals: nil, matches: nil, exists: true, describe: "key K"
        ) == nil)
        #expect(XcodeprojGrader.evaluate(
            value: "x", equals: nil, matches: nil, exists: false, describe: "key K"
        ) != nil)
        #expect(XcodeprojGrader.evaluate(
            value: nil, equals: nil, matches: nil, exists: false, describe: "key K"
        ) == nil)
    }

    @Test("An empty build setting counts as unset")
    func emptyIsUnset() {
        #expect(XcodeprojGrader.evaluate(
            value: "", equals: nil, matches: nil, exists: true, describe: "key K"
        ) == "key K is not set")
    }

    @Test("equals on a missing value reports absence, not a mismatch")
    func missingValue() {
        #expect(XcodeprojGrader.evaluate(
            value: nil, equals: "18.0", matches: nil, exists: nil, describe: "key K"
        ) == "key K is not set")
    }

    @Test("A present container value cannot be string-compared but satisfies exists")
    func containerValue() {
        // `present: true` with `value: nil` is how a plist array/dict arrives.
        #expect(XcodeprojGrader.evaluate(
            value: nil, present: true, equals: nil, matches: nil, exists: true, describe: "CFBundleURLTypes"
        ) == nil)
        let failure = XcodeprojGrader.evaluate(
            value: nil, present: true, equals: "x", matches: nil, exists: nil, describe: "CFBundleURLTypes"
        )
        #expect(failure?.contains("cannot be compared as a string") == true)
    }

    // MARK: - Settings dump

    private func dump(_ json: String) throws -> [XcodebuildSupport.TargetBuildSettings] {
        try JSONDecoder().decode(
            [XcodebuildSupport.TargetBuildSettings].self,
            from: Data(json.utf8)
        )
    }

    @Test("The target matching the scheme wins over other targets in the dump")
    func targetSelection() throws {
        let settings = try dump("""
        [
          {"action": "build", "target": "AppUITests", "buildSettings": {"SWIFT_VERSION": "5.0"}},
          {"action": "build", "target": "App", "buildSettings": {"SWIFT_VERSION": "6.0"}}
        ]
        """)
        #expect(XcodeprojGrader.settings(for: "App", in: settings)?["SWIFT_VERSION"] == "6.0")
    }

    @Test("A scheme with no same-named target falls back to the first entry")
    func targetFallback() throws {
        let settings = try dump("""
        [{"action": "build", "target": "Core", "buildSettings": {"SWIFT_VERSION": "6.0"}}]
        """)
        #expect(XcodeprojGrader.settings(for: "AnotherScheme", in: settings)?["SWIFT_VERSION"] == "6.0")
        #expect(XcodeprojGrader.settings(for: "AnotherScheme", in: []) == nil)
    }

    @Test("The product URL is composed from BUILT_PRODUCTS_DIR and FULL_PRODUCT_NAME")
    func productURL() {
        let url = XcodeprojGrader.productURL(from: [
            "BUILT_PRODUCTS_DIR": "/tmp/Products/Debug-iphonesimulator",
            "FULL_PRODUCT_NAME": "App.app",
        ])
        #expect(url?.path == "/tmp/Products/Debug-iphonesimulator/App.app")

        #expect(XcodeprojGrader.productURL(from: ["FULL_PRODUCT_NAME": "App.app"]) == nil)
        #expect(XcodeprojGrader.productURL(from: [
            "BUILT_PRODUCTS_DIR": "", "FULL_PRODUCT_NAME": "App.app",
        ]) == nil)
    }

    // MARK: - Reading a real product directory

    /// Builds a synthetic `.app` on disk so the plist reading path is exercised
    /// against a real bundle rather than a mocked file system.
    private func makeProduct(
        plist: [String: Any]?,
        extraFiles: [String] = []
    ) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("applebench-product-\(UUID().uuidString)", isDirectory: true)
        let product = root.appendingPathComponent("Fixture.app", isDirectory: true)
        try FileManager.default.createDirectory(at: product, withIntermediateDirectories: true)
        if let plist {
            let data = try PropertyListSerialization.data(
                fromPropertyList: plist, format: .xml, options: 0
            )
            try data.write(to: product.appendingPathComponent("Info.plist"))
        }
        for file in extraFiles {
            let url = product.appendingPathComponent(file)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try Data("x".utf8).write(to: url)
        }
        return product
    }

    @Test("Info.plist values are read from the built bundle")
    func readsInfoPlist() throws {
        let product = try makeProduct(plist: [
            "CFBundleIdentifier": "com.applebench.Fixture",
            "NSCameraUsageDescription": "Scan a document",
            "CFBundleURLTypes": [["CFBundleURLSchemes": ["applebench"]]],
            "UIRequiresFullScreen": true,
        ])
        defer { try? FileManager.default.removeItem(at: product.deletingLastPathComponent()) }

        let plist = try #require(XcodeprojGrader.readInfoPlist(inProductAt: product))
        #expect(plist["CFBundleIdentifier"] as? String == "com.applebench.Fixture")

        // Strings compare; containers only satisfy `exists`.
        #expect(XcodeprojGrader.evaluate(
            value: plist["NSCameraUsageDescription"].flatMap(XcodeprojGrader.describe),
            present: plist["NSCameraUsageDescription"] != nil,
            equals: "Scan a document", matches: nil, exists: nil, describe: "k"
        ) == nil)
        #expect(XcodeprojGrader.evaluate(
            value: plist["CFBundleURLTypes"].flatMap(XcodeprojGrader.describe),
            present: plist["CFBundleURLTypes"] != nil,
            equals: nil, matches: nil, exists: true, describe: "k"
        ) == nil)
        // A key that is simply not there.
        #expect(XcodeprojGrader.evaluate(
            value: plist["NSMicrophoneUsageDescription"].flatMap(XcodeprojGrader.describe),
            present: plist["NSMicrophoneUsageDescription"] != nil,
            equals: nil, matches: nil, exists: true, describe: "NSMicrophoneUsageDescription"
        ) == "NSMicrophoneUsageDescription is not set")
    }

    @Test("Booleans and numbers render for comparison")
    func rendersScalars() throws {
        #expect(XcodeprojGrader.describe("text") == "text")
        #expect(XcodeprojGrader.describe(NSNumber(value: 3)) == "3")
        #expect(XcodeprojGrader.describe([1, 2]) == nil)
    }

    @Test("A product without a readable Info.plist reads as nil")
    func missingInfoPlist() throws {
        let product = try makeProduct(plist: nil)
        defer { try? FileManager.default.removeItem(at: product.deletingLastPathComponent()) }
        #expect(XcodeprojGrader.readInfoPlist(inProductAt: product) == nil)
    }

    @Test("bundle_contains paths resolve inside the built product")
    func bundleContents() throws {
        let product = try makeProduct(plist: [:], extraFiles: ["Assets.car", "en.lproj/Localizable.strings"])
        defer { try? FileManager.default.removeItem(at: product.deletingLastPathComponent()) }

        #expect(FileManager.default.fileExists(atPath: product.appendingPathComponent("Assets.car").path))
        #expect(FileManager.default.fileExists(
            atPath: product.appendingPathComponent("en.lproj/Localizable.strings").path
        ))
        #expect(!FileManager.default.fileExists(atPath: product.appendingPathComponent("Missing.car").path))
    }

    // MARK: - Result composition

    @Test("A grading result names every failed assertion")
    func resultSummary() {
        let start = ContinuousClock.now
        let failed = XcodeprojGrader.result(
            identifier: "xcodeproj",
            start: start,
            failures: ["build setting X is 'a', expected 'b'", "built product does not contain 'Assets.car'"],
            checked: 3,
            evidence: []
        )
        #expect(!failed.passed)
        #expect(failed.summary.contains("2 of 3"))
        #expect(failed.summary.contains("Assets.car"))

        let passed = XcodeprojGrader.result(
            identifier: "xcodeproj", start: start, failures: [], checked: 3, evidence: []
        )
        #expect(passed.passed)
        #expect(passed.summary.contains("3 project assertion(s) hold"))
    }

    // MARK: - Schema

    @Test("An xcodeproj grader decodes from task YAML")
    func decodesFromSpecification() throws {
        let json = """
        {
          "type": "xcodeproj",
          "project": "InfoPlistFixture.xcodeproj",
          "scheme": "InfoPlistFixture",
          "build_settings": [
            {"key": "IPHONEOS_DEPLOYMENT_TARGET", "equals": "18.0"},
            {"key": "SWIFT_VERSION", "matches": "^6"}
          ],
          "info_plist": [{"key": "NSCameraUsageDescription", "exists": true}],
          "bundle_contains": ["Assets.car"]
        }
        """
        let specification = try JSONDecoder().decode(GraderSpecification.self, from: Data(json.utf8))
        guard case .xcodeproj(let configuration) = specification else {
            Issue.record("expected an xcodeproj grader")
            return
        }
        #expect(configuration.scheme == "InfoPlistFixture")
        #expect(configuration.buildSettings.count == 2)
        #expect(configuration.buildSettings[1].matches == "^6")
        #expect(configuration.infoPlist.first?.exists == true)
        #expect(configuration.bundleContains == ["Assets.car"])
        #expect(configuration.requiresBuiltProduct)
        #expect(!configuration.isEmpty)

        // Round-trips without losing the discriminator.
        let encoded = try JSONEncoder().encode(specification)
        #expect(try JSONDecoder().decode(GraderSpecification.self, from: encoded) == specification)
    }

    @Test("A settings-only grader does not require building the product")
    func settingsOnly() {
        let configuration = XcodeprojGraderConfiguration(
            scheme: "App",
            buildSettings: [BuildSettingAssertion(key: "SWIFT_VERSION", matches: "^6")]
        )
        #expect(!configuration.requiresBuiltProduct)
        #expect(!configuration.isEmpty)
        #expect(XcodeprojGraderConfiguration(scheme: "App").isEmpty)
    }
}
