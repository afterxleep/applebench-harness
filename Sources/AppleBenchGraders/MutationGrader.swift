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

        var originals: [(url: URL, text: String)] = []
        // Restoring is not optional: every later grader judges the workspace,
        // and leaving a deliberate break in it would fail them all for a
        // reason that has nothing to do with the agent.
        defer {
            for original in originals {
                try? original.text.write(to: original.url, atomically: true, encoding: .utf8)
            }
        }

        for mutation in configuration.mutations {
            let url = context.workspaceURL.appendingPathComponent(mutation.path)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                throw BenchmarkFailure.graderFailure(
                    grader: identifier,
                    message: "Nothing to mutate at \(mutation.path); the file is missing."
                )
            }
            guard text.contains(mutation.replace) else {
                // The agent rewrote the code the mutation targets. That is not
                // a grading outcome — the check cannot be performed at all, and
                // reporting it as a pass or a fail would both be inventions.
                throw BenchmarkFailure.graderFailure(
                    grader: identifier,
                    message: "\(mutation.path) no longer contains the text this task mutates "
                        + "(\"\(mutation.replace)\"), so the test could not be challenged. "
                        + "The task's mutation needs updating to match the fixture."
                )
            }
            originals.append((url, text))
            try text.replacingOccurrences(of: mutation.replace, with: mutation.with)
                .write(to: url, atomically: true, encoding: .utf8)
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

        let (result, log) = try await XcodebuildSupport.run(
            arguments: arguments,
            logName: "mutation-test.log",
            context: context
        )

        let broke = result.exitCode != 0
        let described = configuration.mutations
            .map { "\($0.path): \"\($0.replace)\" → \"\($0.with)\"" }
            .joined(separator: "; ")
        return GradingResult(
            grader: identifier,
            passed: broke,
            duration: start.duration(to: .now),
            summary: broke
                ? "The tests failed against a deliberately broken app, so they test the behaviour they claim (\(described))"
                : "The tests still passed with the app broken (\(described)), so they do not assert the behaviour the task asked for",
            evidence: [log]
        )
    }
}
