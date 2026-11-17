import AppleBenchCore
import Foundation

/// Verifies Apple project configuration by what it resolves to.
///
/// Build settings come from `xcodebuild -showBuildSettings -json`; Info.plist
/// keys and bundle contents come from a product built into this run's fresh
/// derived data. Nothing here reads `project.pbxproj` text, so an agent cannot
/// satisfy a `project` task by pasting a plausible-looking line into the
/// project file: the configuration has to actually take effect.
public struct XcodeprojGrader: Grader {
    public let identifier = "xcodeproj"
    private let configuration: XcodeprojGraderConfiguration

    public init(configuration: XcodeprojGraderConfiguration) {
        self.configuration = configuration
    }

    public func grade(task: BenchmarkTask, context: GradingContext) async throws -> GradingResult {
        let start = ContinuousClock.now

        let dump = try await XcodebuildSupport.showBuildSettings(
            project: configuration.project,
            workspace: configuration.workspace,
            scheme: configuration.scheme,
            configuration: configuration.configuration,
            destination: configuration.destination,
            logName: "xcodeproj-settings.log",
            context: context
        )
        var evidence = [Artifact(name: "xcodeproj-settings.log", path: "logs/xcodeproj-settings.log")]

        guard let settings = Self.settings(for: configuration.scheme, in: dump) else {
            throw BenchmarkFailure.infrastructureFailure(
                "xcodebuild reported no build settings for scheme '\(configuration.scheme)'"
            )
        }

        var failures: [String] = []
        var checked = 0

        // 1. Resolved build settings.
        for assertion in configuration.buildSettings {
            checked += 1
            let value = settings[assertion.key]
            if let failure = Self.evaluate(
                value: value,
                equals: assertion.equals,
                matches: assertion.matches,
                exists: assertion.exists,
                describe: "build setting \(assertion.key)"
            ) {
                failures.append(failure)
            }
        }

        // 2. Anything that can only be answered by a built product.
        if configuration.requiresBuiltProduct {
            let (buildPassed, buildArtifact) = try await build(context: context)
            evidence.append(buildArtifact)
            if !buildPassed {
                // A product-level assertion on a project that does not build is
                // a legitimate FAIL: the configuration never resolves to a
                // product at all.
                failures.append("the scheme does not build, so the product's Info.plist and bundle cannot be verified")
                checked += configuration.infoPlist.count + configuration.bundleContains.count
            } else {
                guard let productURL = Self.productURL(from: settings) else {
                    throw BenchmarkFailure.infrastructureFailure(
                        "Build settings for '\(configuration.scheme)' lack BUILT_PRODUCTS_DIR/FULL_PRODUCT_NAME"
                    )
                }
                guard FileManager.default.fileExists(atPath: productURL.path) else {
                    failures.append("built product not found at \(productURL.lastPathComponent)")
                    checked += configuration.infoPlist.count + configuration.bundleContains.count
                    return Self.result(
                        identifier: identifier,
                        start: start,
                        failures: failures,
                        checked: checked,
                        evidence: evidence
                    )
                }

                if !configuration.infoPlist.isEmpty {
                    let plist = Self.readInfoPlist(inProductAt: productURL)
                    for assertion in configuration.infoPlist {
                        checked += 1
                        guard let plist else {
                            failures.append("Info.plist missing or unreadable in the built product")
                            continue
                        }
                        if let failure = Self.evaluate(
                            value: plist[assertion.key].flatMap(Self.describe),
                            present: plist[assertion.key] != nil,
                            equals: assertion.equals,
                            matches: assertion.matches,
                            exists: assertion.exists,
                            describe: "Info.plist key \(assertion.key)"
                        ) {
                            failures.append(failure)
                        }
                    }
                }

                for relativePath in configuration.bundleContains {
                    checked += 1
                    let candidate = productURL.appendingPathComponent(relativePath)
                    if !FileManager.default.fileExists(atPath: candidate.path) {
                        failures.append("built product does not contain '\(relativePath)'")
                    }
                }
            }
        }

        return Self.result(
            identifier: identifier,
            start: start,
            failures: failures,
            checked: checked,
            evidence: evidence
        )
    }

    // MARK: - Building

    private func build(context: GradingContext) async throws -> (passed: Bool, artifact: Artifact) {
        var arguments = XcodebuildSupport.baseArguments(
            project: configuration.project,
            workspace: configuration.workspace,
            scheme: configuration.scheme,
            configuration: configuration.configuration,
            destination: configuration.destination,
            context: context
        )
        arguments.append("build")
        let (result, artifact) = try await XcodebuildSupport.run(
            arguments: arguments,
            logName: "xcodeproj-build.log",
            context: context
        )
        return (result.exitCode == 0, artifact)
    }

    // MARK: - Reading the product

    static func settings(for scheme: String, in dump: [XcodebuildSupport.TargetBuildSettings]) -> [String: String]? {
        // A scheme can build several targets; the one named after the scheme is
        // the app under test. Fall back to the first entry only when no target
        // matches, so single-target schemes with a different name still work.
        if let exact = dump.first(where: { $0.target == scheme }) {
            return exact.buildSettings
        }
        return dump.first?.buildSettings
    }

    static func productURL(from settings: [String: String]) -> URL? {
        guard let directory = settings["BUILT_PRODUCTS_DIR"], !directory.isEmpty,
              let name = settings["FULL_PRODUCT_NAME"], !name.isEmpty
        else { return nil }
        return URL(fileURLWithPath: directory).appendingPathComponent(name)
    }

    /// Reads the built product's `Info.plist`, handling both flat bundles
    /// (iOS `.app`) and macOS `Contents/Info.plist` layouts.
    static func readInfoPlist(inProductAt productURL: URL) -> [String: Any]? {
        let candidates = [
            productURL.appendingPathComponent("Info.plist"),
            productURL.appendingPathComponent("Contents/Info.plist"),
        ]
        for candidate in candidates {
            guard let data = try? Data(contentsOf: candidate) else { continue }
            guard let plist = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil
            ) as? [String: Any] else { continue }
            return plist
        }
        return nil
    }

    /// Renders a plist value for `equals`/`matches` comparison. Container
    /// values have no honest string form, so they are reported as absent from
    /// string comparison and can only be asserted with `exists`.
    static func describe(_ value: Any) -> String? {
        switch value {
        case let string as String: string
        case let number as NSNumber: number.description
        default: nil
        }
    }

    // MARK: - Assertion evaluation

    /// Evaluates one assertion, returning a failure message or `nil`.
    static func evaluate(
        value: String?,
        present: Bool? = nil,
        equals: String?,
        matches: String?,
        exists: Bool?,
        describe subject: String
    ) -> String? {
        let isPresent = present ?? (value.map { !$0.isEmpty } ?? false)

        if let exists {
            if exists && !isPresent {
                return "\(subject) is not set"
            }
            if !exists && isPresent {
                return "\(subject) is set to '\(value ?? "")' but must be absent"
            }
        }

        if equals != nil || matches != nil {
            guard isPresent else {
                return "\(subject) is not set"
            }
            guard let value else {
                return "\(subject) has a value that cannot be compared as a string"
            }
            if let equals, value != equals {
                return "\(subject) is '\(value)', expected '\(equals)'"
            }
            if let matches {
                guard let expression = try? NSRegularExpression(pattern: matches) else {
                    return "\(subject): invalid regular expression '\(matches)'"
                }
                let range = NSRange(value.startIndex..<value.endIndex, in: value)
                if expression.firstMatch(in: value, options: [], range: range) == nil {
                    return "\(subject) is '\(value)', expected it to match /\(matches)/"
                }
            }
        }

        return nil
    }

    static func result(
        identifier: String,
        start: ContinuousClock.Instant,
        failures: [String],
        checked: Int,
        evidence: [Artifact]
    ) -> GradingResult {
        let passed = failures.isEmpty
        let summary = passed
            ? "\(checked) project assertion(s) hold in the resolved configuration"
            : "\(failures.count) of \(checked) project assertion(s) failed: " + failures.joined(separator: "; ")
        return GradingResult(
            grader: identifier,
            passed: passed,
            duration: start.duration(to: .now),
            summary: summary,
            evidence: evidence
        )
    }
}
