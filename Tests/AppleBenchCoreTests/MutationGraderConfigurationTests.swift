import Foundation
import Testing
@testable import AppleBenchCore

@Suite("Mutation grader configuration")
struct MutationGraderConfigurationTests {
    @Test("A mutation that replaces text with itself is rejected")
    func noOpMutationIsInvalid() {
        let configuration = MutationGraderConfiguration(
            scheme: "Fixture",
            mutations: [.init(path: "Sources/View.swift", replace: "count += 1", with: "count += 1")]
        )
        #expect(throws: BenchmarkFailure.self) { try configuration.validate() }
    }

    @Test("A mutation grader with nothing to break proves nothing")
    func emptyMutationsAreInvalid() {
        #expect(throws: BenchmarkFailure.self) {
            try MutationGraderConfiguration(scheme: "Fixture", mutations: []).validate()
        }
    }

    @Test("A real mutation validates")
    func realMutationIsValid() {
        #expect(throws: Never.self) {
            try MutationGraderConfiguration(
                scheme: "Fixture",
                mutations: [.init(path: "Sources/View.swift", replace: "count += 1", with: "count += 0")]
            ).validate()
        }
    }

    @Test("Decodes from the shape a task file writes")
    func decodesFromTaskYAMLKeys() throws {
        let json = """
        {
          "scheme": "CounterFixture",
          "tests": ["CounterFixtureUITests"],
          "skip_tests": ["CounterFixtureUITests/Legacy"],
          "mutations": [
            {"path": "Sources/CounterView.swift", "replace": "count += 1", "with": "count += 0"}
          ]
        }
        """
        let configuration = try JSONDecoder().decode(
            MutationGraderConfiguration.self, from: Data(json.utf8)
        )
        #expect(configuration.tests == ["CounterFixtureUITests"])
        #expect(configuration.skipTests == ["CounterFixtureUITests/Legacy"])
        #expect(configuration.mutations.first?.with == "count += 0")
    }

    @Test("A task carrying a mutation grader decodes and validates")
    func taskWithMutationGrader() throws {
        let yaml = """
        id: ui-auto-001
        title: Drive a tap
        category: interaction
        difficulty: 3
        repository:
          url: ./fixtures/CounterFixture
          commit: HEAD
        prompt: "Write a UI test."
        environment:
          platform: ios
          simulator:
            device: "iPhone 17"
            runtime: "iOS 26.5"
        graders:
          - type: mutation
            scheme: CounterFixture
            tests: [CounterFixtureUITests]
            mutations:
              - { path: Sources/CounterView.swift, replace: "count += 1", with: "count += 0" }
        """
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ui-auto-001-\(UUID().uuidString).yaml")
        try yaml.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let task = try TaskLoader.loadTask(from: url)
        guard case .mutation(let configuration) = task.graders.first else {
            Issue.record("expected a mutation grader"); return
        }
        #expect(configuration.mutations.count == 1)
    }
}

/// Mutating by pattern rather than by literal text.
///
/// Tasks that ask the agent to write the test let it choose its own
/// accessibility identifiers, so a mutation pinned to a name from the fixture
/// stops applying the moment the agent renames one. The grader then errors
/// instead of grading, and the model loses a task it may well have solved. A
/// pattern breaks whichever identifier the agent settled on.
@Suite("Mutation by pattern")
struct MutationPatternTests {
    private func mutation(pattern: String, with: String) -> SourceMutation {
        SourceMutation(path: "Sources/View.swift", pattern: pattern, with: with)
    }

    @Test("A pattern rewrites whatever identifier the file uses")
    func patternRewritesAnyIdentifier() throws {
        let source = """
        Text("hi").accessibilityIdentifier("counter-label")
        Button("Go") {}.accessibilityIdentifier("increment-button")
        """
        let applied = try #require(
            try mutation(
                pattern: #"\.accessibilityIdentifier\("([^"]+)"\)"#,
                with: #".accessibilityIdentifier("$1-mutated")"#
            ).apply(to: source)
        )
        #expect(applied.contains(#"accessibilityIdentifier("counter-label-mutated")"#))
        #expect(applied.contains(#"accessibilityIdentifier("increment-button-mutated")"#))
    }

    @Test("A pattern that matches nothing returns nil so the grader can say so")
    func patternWithNoMatchIsNil() throws {
        #expect(try mutation(pattern: #"\.foo\("([^"]+)"\)"#, with: "x").apply(to: "bar") == nil)
    }

    @Test("A literal mutation still applies unchanged")
    func literalStillWorks() throws {
        let m = SourceMutation(path: "p", replace: "count += 1", with: "count += 2")
        #expect(try m.apply(to: "func f() { count += 1 }") == "func f() { count += 2 }")
        #expect(try m.apply(to: "func f() {}") == nil)
    }

    @Test("A mutation must say either what text or what pattern to break")
    func oneOrTheOtherIsRequired() {
        let config = MutationGraderConfiguration(
            project: "P.xcodeproj", workspace: nil, scheme: "P",
            tests: ["T"], skipTests: [],
            mutations: [SourceMutation(path: "p", replace: nil, pattern: nil, with: "x")],
            destination: nil
        )
        #expect(throws: BenchmarkFailure.self) { try config.validate() }
    }

    @Test("A pattern that cannot compile is rejected at validation, not at grading")
    func invalidPatternIsRejectedEarly() {
        // Discovering this while a task is being graded costs the whole run.
        let config = MutationGraderConfiguration(
            project: "P.xcodeproj", workspace: nil, scheme: "P",
            tests: ["T"], skipTests: [],
            mutations: [mutation(pattern: "([unclosed", with: "x")],
            destination: nil
        )
        #expect(throws: BenchmarkFailure.self) { try config.validate() }
    }

    @Test("A pattern that rewrites to itself breaks nothing and is rejected")
    func patternMustChangeSomething() {
        let config = MutationGraderConfiguration(
            project: "P.xcodeproj", workspace: nil, scheme: "P",
            tests: ["T"], skipTests: [],
            mutations: [mutation(pattern: "abc", with: "abc")],
            destination: nil
        )
        #expect(throws: BenchmarkFailure.self) { try config.validate() }
    }

    @Test("Decodes the shape a task file writes")
    func decodesFromYAMLShape() throws {
        let json = """
        { "path": "Sources/View.swift",
          "pattern": "\\\\.accessibilityIdentifier\\\\(\\"([^\\"]+)\\"\\\\)",
          "with": ".accessibilityIdentifier(\\"$1-mutated\\")" }
        """
        let m = try JSONDecoder().decode(SourceMutation.self, from: Data(json.utf8))
        #expect(m.replace == nil)
        #expect(m.pattern != nil)
    }
}
