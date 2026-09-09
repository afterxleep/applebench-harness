import AppleBenchCore
import Foundation

/// Breaks the app, runs the agent's tests, and requires them to notice.
///
/// On a task whose deliverable is a test, the agent authors the thing it is
/// graded by. `xcuitest` runs whatever it wrote, and a test that launches the
/// app and asserts nothing passes exactly like a real one — the task reads as
/// solved and nothing was verified.
///
/// So this grader asks the question a reviewer would: if the behaviour under
/// test were broken, would this test fail? A test that still passes against a
/// deliberately broken app was never testing that behaviour.
///
/// **A passing test run is a FAIL here.** That inversion is the whole grader,
/// and it is why the two states are kept apart: `xcuitest` proves the test
/// passes against a working app, this proves it fails against a broken one.
/// Neither alone says the test is real.
public struct MutationGrader: Grader {
    public let identifier = "mutation"
    private let configuration: MutationGraderConfiguration

    public init(configuration: MutationGraderConfiguration) {
        self.configuration = configuration
    }

    /// One mutation, as a reader of the summary should see it.
    ///
    /// A pattern mutation has no literal to quote. Printing its `replace`
    /// wrote the word nil into published summaries and showed the raw `$1`
    /// template as if it were the text that went in.
    static func describe(_ mutation: SourceMutation) -> String {
        if let literal = mutation.replace {
            return "\(mutation.path): \"\(literal)\" → \"\(mutation.with)\""
        }
        return "\(mutation.path): every match of /\(mutation.pattern ?? "")/ rewritten"
    }

    struct Applied {
        let mutation: SourceMutation
        let original: String
        let mutated: String
    }

    enum Plan {
        /// These mutations applied; those did not and are skipped.
        case apply([Applied], skipped: [SourceMutation])
        /// Nothing applied, and that is a verdict rather than a broken task.
        case fail(summary: String)
    }

    /// Which mutations can be applied to the sources as the agent left them.
    ///
    /// A task may list several mutations that target the same thing in
    /// different shapes — an identifier written as a literal, or computed —
    /// and it is enough that one of them applies. Pattern mutations describe
    /// a class the prompt requires the app to have, so when every pattern
    /// finds nothing the app has none of it, and that is the agent's
    /// failure. A literal describes fixture code; one that has gone means the
    /// task needs updating, and that is an error rather than a verdict.
    static func plan(_ mutations: [SourceMutation], sources: [String: String?]) throws -> Plan {
        var applied: [Applied] = []
        var skipped: [SourceMutation] = []
        for mutation in mutations {
            guard let text = sources[mutation.path] ?? nil else {
                throw BenchmarkFailure.graderFailure(
                    grader: "mutation",
                    message: "Nothing to mutate at \(mutation.path); the file is missing."
                )
            }
            if let mutated = try mutation.apply(to: text) {
                applied.append(Applied(mutation: mutation, original: text, mutated: mutated))
            } else {
                skipped.append(mutation)
            }
        }
        if !applied.isEmpty { return .apply(applied, skipped: skipped) }

        if let literal = skipped.first(where: { $0.replace != nil }) {
            throw BenchmarkFailure.graderFailure(
                grader: "mutation",
                message: "\(literal.path) no longer contains the text this task mutates "
                    + "(\"\(literal.replace ?? "")\"), so the test could not be challenged. "
                    + "The task's mutation needs updating to match the fixture."
            )
        }
        let files = Set(skipped.map(\.path)).sorted().joined(separator: ", ")
        return .fail(summary: "The app has no accessibility identifier left to break in \(files); "
            + "the task requires a test that drives the app by identifier, and there is nothing for one to drive.")
    }

    public func grade(task: BenchmarkTask, context: GradingContext) async throws -> GradingResult {
        let start = ContinuousClock.now
        try configuration.validate()

        // `fake` changes nothing, so there is no test to challenge — asking
        // whether its tests notice a broken app is a question about tests that
        // do not exist. The task still fails for it on the test grader, which
        // is what the solvability check rests on, and skipping here avoids a
        // second `xcodebuild test` against a target that was never created.
        guard context.agent != "fake" else {
            return GradingResult(
                grader: identifier,
                passed: true,
                duration: start.duration(to: .now),
                summary: "Not applicable to the fake agent, which authors no test to challenge",
                evidence: []
            )
        }

        var arguments = XcodebuildSupport.baseArguments(
            project: configuration.project,
            workspace: configuration.workspace,
            scheme: configuration.scheme,
            configuration: nil,
            destination: configuration.destination,
            context: context
        )
        arguments.append("test")
        for identifier in configuration.tests { arguments += ["-only-testing:\(identifier)"] }
        for identifier in configuration.skipTests { arguments += ["-skip-testing:\(identifier)"] }

        // A mutation is meaningful only when the same tests first pass against
        // the workspace the model actually returned. Otherwise a syntax error,
        // missing target, or already-failing assertion would be misreported as
        // proof that the test noticed our deliberate break.
        let (baseline, baselineLog) = try await XcodebuildSupport.run(
            arguments: arguments,
            logName: "mutation-baseline.log",
            context: context
        )
        guard baseline.exitCode == 0 else {
            return GradingResult(
                grader: identifier,
                passed: false,
                duration: start.duration(to: .now),
                summary: "The unmutated tests did not pass, so their failure cannot prove that the mutation was detected",
                evidence: [baselineLog]
            )
        }

        var sources: [String: String?] = [:]
        for mutation in configuration.mutations where sources[mutation.path] == nil {
            let url = context.workspaceURL.appendingPathComponent(mutation.path)
            sources[mutation.path] = try? String(contentsOf: url, encoding: .utf8)
        }
        let applied: [Applied]
        switch try Self.plan(configuration.mutations, sources: sources) {
        case .fail(let summary):
            return GradingResult(
                grader: identifier, passed: false, duration: start.duration(to: .now),
                summary: summary, evidence: []
            )
        case .apply(let plan, _):
            applied = plan
        }

        var originals: [(url: URL, text: String)] = []
        // Restoring is not optional: every later grader judges the workspace,
        // and leaving a deliberate break in it would fail them all for a
        // reason that has nothing to do with the agent.
        defer {
            for original in originals {
                try? original.text.write(to: original.url, atomically: true, encoding: .utf8)
            }
        }
        for one in applied {
            let url = context.workspaceURL.appendingPathComponent(one.mutation.path)
            originals.append((url, one.original))
            try one.mutated.write(to: url, atomically: true, encoding: .utf8)
        }

        let (result, log) = try await XcodebuildSupport.run(
            arguments: arguments,
            logName: "mutation-test.log",
            context: context
        )

        let broke = result.exitCode != 0
        let described = applied.map { Self.describe($0.mutation) }.joined(separator: "; ")
        return GradingResult(
            grader: identifier,
            passed: broke,
            duration: start.duration(to: .now),
            summary: broke
                ? "The tests failed against a deliberately broken app, so they test the behaviour they claim (\(described))"
                : "The tests still passed with the app broken (\(described)), so they do not assert the behaviour the task asked for",
            evidence: [baselineLog, log]
        )
    }
}
