import Foundation
import Testing
@testable import AppleBenchCore

@Suite("Task YAML decoding")
struct TaskDecodingTests {
    private func write(_ yaml: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("applebench-test-\(UUID().uuidString).yaml")
        try yaml.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test("Full task with every grader type decodes")
    func fullTask() throws {
        let yaml = """
        id: navigation-001
        title: Fix Settings navigation crash
        category: runtime
        difficulty: 1
        tags: [navigation, swiftui]

        repository:
          url: https://github.com/applebench/AsyncLoadFixture.git
          commit: 4a91abc

        prompt: |
          Opening Settings causes the app to crash.
          Find the problem, fix it, and verify your solution.

        environment:
          xcode: "27.0"
          platform: ios
          simulator:
            device: "iPhone 17 Pro"
            runtime: "iOS 27.0"

        limits:
          timeout_seconds: 900
          max_cost_usd: 5
          max_tokens: 100000

        graders:
          - type: build
            scheme: AsyncLoadFixture

          - type: xctest
            scheme: AsyncLoadFixture
            test_plan: BenchmarkTests

          - type: xcuitest
            scheme: AsyncLoadFixtureUITests
            tests:
              - SettingsNavigationTests/testOpeningSettings

          - type: runtime
            scheme: AsyncLoadFixture
            launch:
              bundle_identifier: com.applebench.AsyncLoadFixture
            must_not_crash: true

          - type: file
            assertions:
              - path: App/Configuration.swift
                contains: "retainCount"
        """
        let task = try TaskLoader.loadTask(from: write(yaml))

        #expect(task.id == "navigation-001")
        #expect(task.category == .runtime)
        #expect(task.difficulty == 1)
        #expect(task.tags == ["navigation", "swiftui"])
        #expect(task.repository.commit == "4a91abc")
        #expect(task.environment.xcode == "27.0")
        #expect(task.environment.simulator?.device == "iPhone 17 Pro")
        #expect(task.limits.timeoutSeconds == 900)
        #expect(task.limits.maxCostUSD == 5)
        #expect(task.limits.maxTokens == 100_000)
        #expect(task.graders.count == 5)

        guard case .build(let build) = task.graders[0] else { Issue.record("expected build"); return }
        #expect(build.scheme == "AsyncLoadFixture")

        guard case .xctest(let xctest) = task.graders[1] else { Issue.record("expected xctest"); return }
        #expect(xctest.testPlan == "BenchmarkTests")

        guard case .xcuitest(let ui) = task.graders[2] else { Issue.record("expected xcuitest"); return }
        #expect(ui.tests == ["SettingsNavigationTests/testOpeningSettings"])

        guard case .runtime(let runtime) = task.graders[3] else { Issue.record("expected runtime"); return }
        #expect(runtime.launch.bundleIdentifier == "com.applebench.AsyncLoadFixture")
        #expect(runtime.mustNotCrash)
        #expect(runtime.observationSeconds == 5)

        guard case .file(let file) = task.graders[4] else { Issue.record("expected file"); return }
        #expect(file.assertions.first?.contains == "retainCount")
    }

    @Test("Limits default when omitted")
    func limitsDefault() throws {
        let yaml = """
        id: minimal-001
        title: Minimal
        repository: {url: /tmp/repo, commit: HEAD}
        prompt: Do something.
        environment: {platform: ios}
        """
        let task = try TaskLoader.loadTask(from: write(yaml))
        #expect(task.limits.timeoutSeconds == RunLimits.defaultTimeoutSeconds)
        #expect(task.limits.maxCostUSD == nil)
        #expect(task.graders.isEmpty)
        #expect(task.tags.isEmpty)
        #expect(task.category == nil)
        #expect(task.difficulty == nil)
    }

    @Test("Difficulty outside 1...10 is rejected", arguments: [0, 11, -1, 42])
    func difficultyOutOfRange(_ difficulty: Int) throws {
        let yaml = """
        id: bad-005
        title: Bad
        category: build
        difficulty: \(difficulty)
        repository: {url: /tmp/repo, commit: HEAD}
        prompt: Do something.
        environment: {platform: ios}
        """
        #expect(throws: BenchmarkFailure.self) {
            try TaskLoader.loadTask(from: write(yaml))
        }
    }

    @Test("Every difficulty in 1...10 is accepted", arguments: Array(BenchmarkTask.difficultyRange))
    func difficultyInRange(_ difficulty: Int) throws {
        let yaml = """
        id: ok-005
        title: OK
        category: visual
        difficulty: \(difficulty)
        repository: {url: /tmp/repo, commit: HEAD}
        prompt: Do something.
        environment: {platform: ios}
        """
        let task = try TaskLoader.loadTask(from: write(yaml))
        #expect(task.difficulty == difficulty)
        #expect(task.category == .visual)
    }

    @Test("Unknown category is rejected")
    func unknownCategory() throws {
        let yaml = """
        id: bad-006
        title: Bad
        category: telepathy
        repository: {url: /tmp/repo, commit: HEAD}
        prompt: Do something.
        environment: {platform: ios}
        """
        #expect(throws: BenchmarkFailure.self) {
            try TaskLoader.loadTask(from: write(yaml))
        }
    }

    @Test("Unknown grader type is rejected")
    func unknownGrader() throws {
        let yaml = """
        id: bad-001
        title: Bad
        repository: {url: /tmp/repo, commit: HEAD}
        prompt: Do something.
        environment: {platform: ios}
        graders:
          - type: telepathy
        """
        #expect(throws: BenchmarkFailure.self) {
            try TaskLoader.loadTask(from: write(yaml))
        }
    }

    @Test("Missing prompt is rejected")
    func missingPrompt() throws {
        let yaml = """
        id: bad-002
        title: Bad
        repository: {url: /tmp/repo, commit: HEAD}
        environment: {platform: ios}
        """
        #expect(throws: BenchmarkFailure.self) {
            try TaskLoader.loadTask(from: write(yaml))
        }
    }

    @Test("Task id with path characters is rejected")
    func hostileTaskID() throws {
        let yaml = """
        id: "../../etc/passwd"
        title: Bad
        repository: {url: /tmp/repo, commit: HEAD}
        prompt: Do something.
        environment: {platform: ios}
        """
        #expect(throws: BenchmarkFailure.self) {
            try TaskLoader.loadTask(from: write(yaml))
        }
    }

    @Test("Runtime grader without scheme is rejected")
    func runtimeWithoutScheme() throws {
        let yaml = """
        id: bad-003
        title: Bad
        repository: {url: /tmp/repo, commit: HEAD}
        prompt: Do something.
        environment:
          platform: ios
          simulator: {device: "iPhone 17", runtime: "iOS 26.5"}
        graders:
          - type: runtime
            launch: {bundle_identifier: com.example.app}
        """
        #expect(throws: BenchmarkFailure.self) {
            try TaskLoader.loadTask(from: write(yaml))
        }
    }

    @Test("Simulator-dependent graders require a simulator declaration")
    func simulatorRequired() throws {
        let yaml = """
        id: bad-004
        title: Bad
        repository: {url: /tmp/repo, commit: HEAD}
        prompt: Do something.
        environment: {platform: ios}
        graders:
          - type: xcuitest
            scheme: App
        """
        #expect(throws: BenchmarkFailure.self) {
            try TaskLoader.loadTask(from: write(yaml))
        }
    }

    @Test("An xcodeproj grader loads and validates from task YAML")
    func xcodeprojGrader() throws {
        let yaml = """
        id: project-001
        title: Camera permission never prompts
        category: project
        difficulty: 2
        repository: {url: /tmp/repo, commit: HEAD}
        prompt: The camera screen never asks for permission.
        environment:
          platform: ios
          simulator: {device: "iPhone 17", runtime: "iOS 26.5"}
        graders:
          - type: xcodeproj
            project: TargetMembershipFixture.xcodeproj
            scheme: TargetMembershipFixture
            build_settings:
              - key: IPHONEOS_DEPLOYMENT_TARGET
                equals: "18.0"
            info_plist:
              - key: NSCameraUsageDescription
                exists: true
            bundle_contains:
              - Assets.car
        """
        let task = try TaskLoader.loadTask(from: write(yaml))
        guard case .xcodeproj(let configuration) = task.graders[0] else {
            Issue.record("expected an xcodeproj grader")
            return
        }
        #expect(configuration.scheme == "TargetMembershipFixture")
        #expect(configuration.buildSettings.first?.equals == "18.0")
        #expect(configuration.infoPlist.first?.key == "NSCameraUsageDescription")
        #expect(configuration.bundleContains == ["Assets.car"])
    }

    @Test("An xcodeproj grader that asserts nothing is rejected")
    func emptyXcodeprojGrader() throws {
        let yaml = """
        id: bad-007
        title: Bad
        repository: {url: /tmp/repo, commit: HEAD}
        prompt: Do something.
        environment:
          platform: ios
          simulator: {device: "iPhone 17", runtime: "iOS 26.5"}
        graders:
          - type: xcodeproj
            scheme: App
        """
        #expect(throws: BenchmarkFailure.self) {
            try TaskLoader.loadTask(from: write(yaml))
        }
    }

    @Test("Separate evaluation file supplies graders")
    func splitEvaluation() throws {
        let taskYAML = """
        id: split-001
        title: Split
        repository: {url: /tmp/repo, commit: HEAD}
        prompt: Do something.
        environment: {platform: ios}
        """
        let evaluationYAML = """
        graders:
          - type: build
            scheme: App
        """
        let task = try TaskLoader.loadTask(from: write(taskYAML), evaluation: write(evaluationYAML))
        #expect(task.graders.count == 1)
        #expect(task.graders.first?.type == .build)
    }

    @Test("Suite decodes and rejects empty task lists")
    func suite() throws {
        let suite = try TaskLoader.loadSuite(from: write("""
        id: core
        name: AppleBench Core
        tasks: [a-001, b-001]
        """))
        #expect(suite.tasks == ["a-001", "b-001"])

        #expect(throws: BenchmarkFailure.self) {
            try TaskLoader.loadSuite(from: write("""
            id: empty
            name: Empty
            tasks: []
            """))
        }
    }

    @Test("Grader specifications round-trip through Codable")
    func graderRoundTrip() throws {
        let specifications: [GraderSpecification] = [
            .build(BuildGraderConfiguration(project: "App.xcodeproj", scheme: "App")),
            .xctest(XCTestGraderConfiguration(scheme: "App", testPlan: "Plan", tests: ["A/b"], skipTests: ["C/d"])),
            .file(FileGraderConfiguration(assertions: [FileAssertion(path: "a.swift", contains: "x")])),
            .runtime(RuntimeGraderConfiguration(
                scheme: "App",
                launch: RuntimeLaunchConfiguration(bundleIdentifier: "com.x.y")
            )),
        ]
        let data = try JSONEncoder().encode(specifications)
        let decoded = try JSONDecoder().decode([GraderSpecification].self, from: data)
        #expect(decoded == specifications)
    }

    @Test("A uiflow grader keeps the region its appearance check is limited to")
    func decodesAppearanceRegion() throws {
        // The region was declared, given a coding key, and never decoded, so
        // every appearance check silently measured the whole screen. A screen
        // always adapts, so the check could not fail and nothing said so.
        let yaml = """
        id: t-1
        title: T
        repository: {url: ./x, commit: HEAD}
        prompt: p
        environment:
          platform: ios
          simulator: {device: "iPhone 17", runtime: "iOS 26.5"}
        graders:
          - type: uiflow
            scheme: S
            bundle_id: com.example.S
            appearance_must_differ: true
            appearance_region: the-card
            assertions:
              - {text: Hello}
        """
        let task = try TaskLoader.loadTask(from: write(yaml))
        guard case .uiflow(let configuration) = task.graders[0] else {
            Issue.record("expected a uiflow grader")
            return
        }
        #expect(configuration.appearanceMustDiffer)
        #expect(configuration.appearanceRegion == "the-card")
    }
}
