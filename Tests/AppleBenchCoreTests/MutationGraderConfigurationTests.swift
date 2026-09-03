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
