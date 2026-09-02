import Foundation

/// A grader entry in a task definition.
///
/// Modeled as an enum with strongly typed associated configuration so the
/// schema stays fully typed without collapsing into `[String: Any]`. The YAML
/// discriminator is the `type` key.
public enum GraderSpecification: Sendable, Equatable {
    case build(BuildGraderConfiguration)
    case xctest(XCTestGraderConfiguration)
    case xcuitest(XCUITestGraderConfiguration)
    case file(FileGraderConfiguration)
    case runtime(RuntimeGraderConfiguration)
    case xcodeproj(XcodeprojGraderConfiguration)
    case uiflow(UIFlowGraderConfiguration)

    /// The `type` discriminator value for this grader.
    public var type: GraderType {
        switch self {
        case .build: .build
        case .xctest: .xctest
        case .xcuitest: .xcuitest
        case .file: .file
        case .runtime: .runtime
        case .xcodeproj: .xcodeproj
        case .uiflow: .uiflow
        }
    }
}

public enum GraderType: String, Sendable, Codable, CaseIterable {
    case build
    case xctest
    case xcuitest
    case file
    case runtime
    case xcodeproj
    case uiflow
}

extension GraderSpecification: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(GraderType.self, forKey: .type)
        switch type {
        case .build:
            self = .build(try BuildGraderConfiguration(from: decoder))
        case .xctest:
            self = .xctest(try XCTestGraderConfiguration(from: decoder))
        case .xcuitest:
            self = .xcuitest(try XCUITestGraderConfiguration(from: decoder))
        case .file:
            self = .file(try FileGraderConfiguration(from: decoder))
        case .runtime:
            self = .runtime(try RuntimeGraderConfiguration(from: decoder))
        case .xcodeproj:
            self = .xcodeproj(try XcodeprojGraderConfiguration(from: decoder))
        case .uiflow:
            self = .uiflow(try UIFlowGraderConfiguration(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        switch self {
        case .build(let configuration):
            try configuration.encode(to: encoder)
        case .xctest(let configuration):
            try configuration.encode(to: encoder)
        case .xcuitest(let configuration):
            try configuration.encode(to: encoder)
        case .file(let configuration):
            try configuration.encode(to: encoder)
        case .runtime(let configuration):
            try configuration.encode(to: encoder)
        case .xcodeproj(let configuration):
            try configuration.encode(to: encoder)
        case .uiflow(let configuration):
            try configuration.encode(to: encoder)
        }
    }
}

// MARK: - Build

public struct BuildGraderConfiguration: Sendable, Codable, Equatable {
    /// Path to an `.xcodeproj`, relative to the workspace root. Optional when
    /// the workspace root is unambiguous for `xcodebuild`.
    public var project: String?
    /// Path to an `.xcworkspace`, relative to the workspace root.
    public var workspace: String?
    public var scheme: String
    /// Build configuration, e.g. `Debug`.
    public var configuration: String?
    /// Explicit `-destination` value. When absent, the runner derives one from
    /// the task's simulator requirement.
    public var destination: String?

    public init(
        project: String? = nil,
        workspace: String? = nil,
        scheme: String,
        configuration: String? = nil,
        destination: String? = nil
    ) {
        self.project = project
        self.workspace = workspace
        self.scheme = scheme
        self.configuration = configuration
        self.destination = destination
    }
}

// MARK: - XCTest / XCUITest

public struct XCTestGraderConfiguration: Sendable, Codable, Equatable {
    public var project: String?
    public var workspace: String?
    public var scheme: String
    public var testPlan: String?
    /// Explicit test identifiers passed as `-only-testing:` entries,
    /// e.g. `CounterTests/testPersistence`.
    public var tests: [String]
    /// Test identifiers passed as `-skip-testing:` entries.
    public var skipTests: [String]
    public var destination: String?

    public init(
        project: String? = nil,
        workspace: String? = nil,
        scheme: String,
        testPlan: String? = nil,
        tests: [String] = [],
        skipTests: [String] = [],
        destination: String? = nil
    ) {
        self.project = project
        self.workspace = workspace
        self.scheme = scheme
        self.testPlan = testPlan
        self.tests = tests
        self.skipTests = skipTests
        self.destination = destination
    }

    enum CodingKeys: String, CodingKey {
        case project, workspace, scheme, tests, destination
        case testPlan = "test_plan"
        case skipTests = "skip_tests"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        project = try container.decodeIfPresent(String.self, forKey: .project)
        workspace = try container.decodeIfPresent(String.self, forKey: .workspace)
        scheme = try container.decode(String.self, forKey: .scheme)
        testPlan = try container.decodeIfPresent(String.self, forKey: .testPlan)
        tests = try container.decodeIfPresent([String].self, forKey: .tests) ?? []
        skipTests = try container.decodeIfPresent([String].self, forKey: .skipTests) ?? []
        destination = try container.decodeIfPresent(String.self, forKey: .destination)
    }
}

/// UI tests share the xcodebuild test configuration shape.
public typealias XCUITestGraderConfiguration = XCTestGraderConfiguration

// MARK: - File

public struct FileGraderConfiguration: Sendable, Codable, Equatable {
    public var assertions: [FileAssertion]

    public init(assertions: [FileAssertion]) {
        self.assertions = assertions
    }
}

/// A deterministic assertion about the final workspace state.
public struct FileAssertion: Sendable, Codable, Equatable {
    /// Workspace-relative path the assertion applies to. If `glob` is
    /// `true`, the path is treated as a glob pattern (a single `*` or
    /// `**` segment is supported, matching the conventional
    /// "subdirectory somewhere" use case).
    public var path: String
    /// Requires the file to exist (`true`) or not exist (`false`).
    public var exists: Bool?
    /// Requires the file contents to contain this literal substring.
    public var contains: String?
    /// Requires the file contents to match this regular expression.
    public var matches: String?
    /// Requires the run diff to include (`true`) or exclude (`false`) this path.
    public var changed: Bool?
    /// Requires the file to be at least this many bytes. Catches
    /// stub/empty deliverables without dictating content.
    public var minSize: Int?
    /// Requires the file to parse as JSON. `is_json` exists so the grader
    /// can verify a deliverable like `build-settings.json` is a real
    /// JSON dump and not a renamed text file.
    public var isJSON: Bool?
    /// Requires the file to carry the PNG signature. Screenshots are the one
    /// deliverable the benchmark checks that is not text, and `contains` and
    /// `matches` cannot see them: those read the file as UTF-8, which a real
    /// PNG is not, so an image can only ever be reported unreadable.
    public var isPNG: Bool?
    /// When `true`, `path` is a glob pattern rather than a literal
    /// path. The assertion matches if *any* file under the workspace
    /// matches the glob. Used for "this artifact must exist somewhere
    /// in the workspace" — outcome-focused, not location-prescriptive.
    public var glob: Bool?

    public init(
        path: String,
        exists: Bool? = nil,
        contains: String? = nil,
        matches: String? = nil,
        changed: Bool? = nil,
        minSize: Int? = nil,
        isJSON: Bool? = nil,
        isPNG: Bool? = nil,
        glob: Bool? = nil
    ) {
        self.path = path
        self.exists = exists
        self.contains = contains
        self.matches = matches
        self.changed = changed
        self.minSize = minSize
        self.isJSON = isJSON
        self.isPNG = isPNG
        self.glob = glob
    }

    enum CodingKeys: String, CodingKey {
        case path, exists, contains, matches, changed
        case minSize = "min_size"
        case isJSON = "is_json"
        case isPNG = "is_png"
        case glob
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        exists = try container.decodeIfPresent(Bool.self, forKey: .exists)
        contains = try container.decodeIfPresent(String.self, forKey: .contains)
        matches = try container.decodeIfPresent(String.self, forKey: .matches)
        changed = try container.decodeIfPresent(Bool.self, forKey: .changed)
        minSize = try container.decodeIfPresent(Int.self, forKey: .minSize)
        isJSON = try container.decodeIfPresent(Bool.self, forKey: .isJSON)
        isPNG = try container.decodeIfPresent(Bool.self, forKey: .isPNG)
        glob = try container.decodeIfPresent(Bool.self, forKey: .glob)
    }
}

// MARK: - Runtime

public struct RuntimeGraderConfiguration: Sendable, Codable, Equatable {
    public var project: String?
    public var workspace: String?
    /// Scheme used to build the app before installing it on the simulator.
    /// When absent, the runtime grader expects a build grader to have produced
    /// products already is not supported in v1 — a scheme is required in
    /// practice and `validate` flags its absence.
    public var scheme: String?
    public var launch: RuntimeLaunchConfiguration
    public var mustNotCrash: Bool
    /// How long the launched process must survive, in seconds.
    public var observationSeconds: Int

    public init(
        project: String? = nil,
        workspace: String? = nil,
        scheme: String? = nil,
        launch: RuntimeLaunchConfiguration,
        mustNotCrash: Bool = true,
        observationSeconds: Int = 5
    ) {
        self.project = project
        self.workspace = workspace
        self.scheme = scheme
        self.launch = launch
        self.mustNotCrash = mustNotCrash
        self.observationSeconds = observationSeconds
    }

    enum CodingKeys: String, CodingKey {
        case project, workspace, scheme, launch
        case mustNotCrash = "must_not_crash"
        case observationSeconds = "observation_seconds"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        project = try container.decodeIfPresent(String.self, forKey: .project)
        workspace = try container.decodeIfPresent(String.self, forKey: .workspace)
        scheme = try container.decodeIfPresent(String.self, forKey: .scheme)
        launch = try container.decode(RuntimeLaunchConfiguration.self, forKey: .launch)
        mustNotCrash = try container.decodeIfPresent(Bool.self, forKey: .mustNotCrash) ?? true
        observationSeconds = try container.decodeIfPresent(Int.self, forKey: .observationSeconds) ?? 5
    }
}

public struct RuntimeLaunchConfiguration: Sendable, Codable, Equatable {
    public var bundleIdentifier: String

    public init(bundleIdentifier: String) {
        self.bundleIdentifier = bundleIdentifier
    }

    enum CodingKeys: String, CodingKey {
        case bundleIdentifier = "bundle_identifier"
    }
}

// MARK: - Xcodeproj

/// Grades Apple project configuration by what it *resolves to*, never by the
/// text of `project.pbxproj`.
///
/// `build_settings` are answered by `xcodebuild -showBuildSettings -json`.
/// `info_plist` and `bundle_contains` are answered by building the scheme into
/// the run's fresh derived data and reading the product bundle — so a hand-
/// edited pbxproj that does not actually take effect cannot pass.
public struct XcodeprojGraderConfiguration: Sendable, Codable, Equatable {
    public var project: String?
    public var workspace: String?
    public var scheme: String
    public var configuration: String?
    public var destination: String?
    public var buildSettings: [BuildSettingAssertion]
    public var infoPlist: [InfoPlistAssertion]
    /// Paths that must exist inside the built `.app`, relative to its root.
    public var bundleContains: [String]

    public init(
        project: String? = nil,
        workspace: String? = nil,
        scheme: String,
        configuration: String? = nil,
        destination: String? = nil,
        buildSettings: [BuildSettingAssertion] = [],
        infoPlist: [InfoPlistAssertion] = [],
        bundleContains: [String] = []
    ) {
        self.project = project
        self.workspace = workspace
        self.scheme = scheme
        self.configuration = configuration
        self.destination = destination
        self.buildSettings = buildSettings
        self.infoPlist = infoPlist
        self.bundleContains = bundleContains
    }

    /// True when nothing can be answered from the settings dump alone.
    public var requiresBuiltProduct: Bool {
        !infoPlist.isEmpty || !bundleContains.isEmpty
    }

    public var isEmpty: Bool {
        buildSettings.isEmpty && infoPlist.isEmpty && bundleContains.isEmpty
    }

    enum CodingKeys: String, CodingKey {
        case project, workspace, scheme, configuration, destination
        case buildSettings = "build_settings"
        case infoPlist = "info_plist"
        case bundleContains = "bundle_contains"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        project = try container.decodeIfPresent(String.self, forKey: .project)
        workspace = try container.decodeIfPresent(String.self, forKey: .workspace)
        scheme = try container.decode(String.self, forKey: .scheme)
        configuration = try container.decodeIfPresent(String.self, forKey: .configuration)
        destination = try container.decodeIfPresent(String.self, forKey: .destination)
        buildSettings = try container.decodeIfPresent([BuildSettingAssertion].self, forKey: .buildSettings) ?? []
        infoPlist = try container.decodeIfPresent([InfoPlistAssertion].self, forKey: .infoPlist) ?? []
        bundleContains = try container.decodeIfPresent([String].self, forKey: .bundleContains) ?? []
    }
}

/// An assertion about one resolved build setting.
public struct BuildSettingAssertion: Sendable, Codable, Equatable {
    public var key: String
    /// Exact string equality against the resolved value.
    public var equals: String?
    /// Regular expression the resolved value must match.
    public var matches: String?
    /// Requires the setting to be present (`true`) or absent/empty (`false`).
    public var exists: Bool?

    public init(key: String, equals: String? = nil, matches: String? = nil, exists: Bool? = nil) {
        self.key = key
        self.equals = equals
        self.matches = matches
        self.exists = exists
    }
}

/// An assertion about one key in the *built* product's `Info.plist`.
public struct InfoPlistAssertion: Sendable, Codable, Equatable {
    public var key: String
    public var equals: String?
    public var matches: String?
    public var exists: Bool?

    public init(key: String, equals: String? = nil, matches: String? = nil, exists: Bool? = nil) {
        self.key = key
        self.equals = equals
        self.matches = matches
        self.exists = exists
    }
}

// MARK: - UI flow

/// Drives the running app through FlowDeck and judges the screen it leaves.
///
/// The other graders ask `xcodebuild` a question. This one asks the device.
/// That is the point: rotation, system language, hardware buttons and the
/// accessibility tree of a live app are either awkward or impossible to reach
/// from an XCUITest, and two of them — orientation and language — have no
/// `simctl` primitive at all.
///
/// Verification stays deliberately plain. Run a batch of steps, optionally
/// press some hardware buttons, then make a handful of deterministic claims
/// about the resulting accessibility tree. No pixel comparison, no test target
/// for the agent to discover, and nothing describing the assertions anywhere
/// inside the workspace — they live here, in the task file, which the agent
/// never sees.
public struct UIFlowGraderConfiguration: Sendable, Codable, Equatable {
    public var project: String?
    public var workspace: String?
    /// Scheme built and installed before the flow runs.
    public var scheme: String
    /// Bundle identifier used to launch and terminate the app.
    public var bundleIdentifier: String
    /// Device state applied before launch and reset afterwards.
    public var deviceState: SimulatorDeviceState?
    /// Device state applied *after* the steps have run, before the final read.
    ///
    /// Rotating before launch and rotating a running app are different tests.
    /// A layout constant captured once at start-up is correct either way if the
    /// app is launched already rotated; it only goes wrong when the device
    /// turns underneath it. That second case is the one users hit.
    public var afterState: SimulatorDeviceState?
    /// Steps passed verbatim to `flowdeck ui simulator batch --steps`. Carried
    /// rather than modeled, so a new CLI action needs no harness change.
    public var steps: [JSONValue]
    /// Hardware buttons pressed after the steps, over the Indigo HID path:
    /// `home`, `lock`, `app-switcher`, `siri`, `volumeup`, `volumedown`.
    public var buttons: [String]
    /// What must be true of the screen once the flow has finished.
    public var assertions: [UIFlowAssertion]
    /// Seconds to let the UI settle after the buttons before the final read.
    public var settleSeconds: Int

    public init(
        project: String? = nil,
        workspace: String? = nil,
        scheme: String,
        bundleIdentifier: String,
        deviceState: SimulatorDeviceState? = nil,
        afterState: SimulatorDeviceState? = nil,
        steps: [JSONValue] = [],
        buttons: [String] = [],
        assertions: [UIFlowAssertion] = [],
        settleSeconds: Int = 2
    ) {
        self.project = project
        self.workspace = workspace
        self.scheme = scheme
        self.bundleIdentifier = bundleIdentifier
        self.deviceState = deviceState
        self.afterState = afterState
        self.steps = steps
        self.buttons = buttons
        self.assertions = assertions
        self.settleSeconds = settleSeconds
    }

    enum CodingKeys: String, CodingKey {
        case project, workspace, scheme, steps, buttons, assertions
        case bundleIdentifier = "bundle_id"
        case deviceState = "device_state"
        case afterState = "after_state"
        case settleSeconds = "settle_seconds"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        project = try container.decodeIfPresent(String.self, forKey: .project)
        workspace = try container.decodeIfPresent(String.self, forKey: .workspace)
        scheme = try container.decode(String.self, forKey: .scheme)
        bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
        deviceState = try container.decodeIfPresent(SimulatorDeviceState.self, forKey: .deviceState)
        afterState = try container.decodeIfPresent(SimulatorDeviceState.self, forKey: .afterState)
        steps = try container.decodeIfPresent([JSONValue].self, forKey: .steps) ?? []
        buttons = try container.decodeIfPresent([String].self, forKey: .buttons) ?? []
        assertions = try container.decodeIfPresent([UIFlowAssertion].self, forKey: .assertions) ?? []
        settleSeconds = try container.decodeIfPresent(Int.self, forKey: .settleSeconds) ?? 2
    }

    public func validate() throws {
        guard !assertions.isEmpty else {
            throw BenchmarkFailure.invalidTask(
                "A uiflow grader with no assertions cannot fail, so it grades nothing"
            )
        }
        for assertion in assertions { try assertion.validate() }
        try deviceState?.validate()
        try afterState?.validate()
        let known: Set<String> = ["home", "lock", "side-button", "app-switcher", "siri", "volumeup", "volumedown"]
        for button in buttons where !known.contains(button) {
            throw BenchmarkFailure.invalidTask(
                "uiflow has no hardware button '\(button)'. Valid: " + known.sorted().joined(separator: ", ")
            )
        }
    }
}
