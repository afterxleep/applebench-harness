import Foundation

/// The device state a grader puts the run's simulator into before it judges.
///
/// The existing suite grades every app in one state: portrait, English, light,
/// default text size, hardware keyboard attached. A defect that only appears
/// outside that state is invisible to it. This is how a task says "grade this
/// rotated", or "grade this in Arabic", and it is applied after the agent has
/// exited, against the simulator provisioned for the run.
///
/// **Why FlowDeck and not `xcrun`.** Appearance, content size and contrast have
/// `simctl ui` equivalents. Orientation and language do not — there is no
/// `simctl` primitive for either. Rotation is a GSEvent plus a poll of
/// `com.apple.backboardd.plist` until the physical orientation actually
/// matches, and language is a write to the device's `.GlobalPreferences.plist`
/// followed by a reboot. Shelling to the CLI that already implements both,
/// correctly, is the difference between a task that can be graded and one that
/// cannot.
///
/// Every field is optional and an absent field is never "reset to default": a
/// state issues commands only for what it names, and `resetCommands` undoes
/// only that. A grader that reset everything would be silently changing
/// conditions the task never asked about.
public struct SimulatorDeviceState: Sendable, Codable, Equatable {
    /// `portrait`, `portrait-upside-down`, `landscape-left`, `landscape-right`.
    ///
    /// Applied where the task puts it. In `device_state` it runs before launch,
    /// which only takes on a device whose home screen rotates — iPad. On iPhone
    /// SpringBoard is portrait-only and iOS refuses the rotation, so an iPhone
    /// task turns the device under the running app with `after_state` instead.
    public var orientation: String?
    /// A language code, e.g. `ar`, `de`, `ja`. Applying it reboots the device.
    public var language: String?
    /// A locale identifier, e.g. `ar_SA`. Only meaningful alongside `language`.
    public var locale: String?
    /// `light` or `dark`.
    public var appearance: String?
    /// A content size category, e.g. `accessibility-extra-extra-extra-large`.
    public var contentSize: String?
    /// `enabled` or `disabled`.
    public var increaseContrast: String?
    /// `on` or `off`. Turning it **off** is what makes the software keyboard
    /// appear when a field gains focus, which is the only way to grade
    /// keyboard-avoidance layout.
    public var hardwareKeyboard: String?
    /// Status bar overrides, keyed by the CLI's kebab-case flag name without
    /// the leading dashes — `battery-level`, `operator-name`, `cellular-mode`.
    public var statusBar: [String: String]?

    public init(
        orientation: String? = nil,
        language: String? = nil,
        locale: String? = nil,
        appearance: String? = nil,
        contentSize: String? = nil,
        increaseContrast: String? = nil,
        hardwareKeyboard: String? = nil,
        statusBar: [String: String]? = nil
    ) {
        self.orientation = orientation
        self.language = language
        self.locale = locale
        self.appearance = appearance
        self.contentSize = contentSize
        self.increaseContrast = increaseContrast
        self.hardwareKeyboard = hardwareKeyboard
        self.statusBar = statusBar
    }

    enum CodingKeys: String, CodingKey {
        case orientation, language, locale, appearance
        case contentSize = "content_size"
        case increaseContrast = "increase_contrast"
        case hardwareKeyboard = "hardware_keyboard"
        case statusBar = "status_bar"
    }

    /// The flag names `flowdeck simulator status-bar override` accepts. An
    /// unknown key is a task-authoring mistake, and passing it through would
    /// surface as an opaque CLI usage error at grading time instead.
    static let statusBarFlags: Set<String> = [
        "time", "data-network", "wifi-mode", "wifi-bars", "cellular-mode",
        "cellular-bars", "operator-name", "battery-state", "battery-level",
    ]

    static let defaultOrientation = "portrait"

    public var isEmpty: Bool {
        applyCommands(udid: "").isEmpty
    }

    /// Names every setting this state changes, for the grader's summary. A run
    /// that does not say which state it graded in cannot be read later.
    public var summary: String {
        var parts: [String] = []
        if let orientation { parts.append("orientation=\(orientation)") }
        if let language { parts.append("language=\(language)") }
        if let locale { parts.append("locale=\(locale)") }
        if let appearance { parts.append("appearance=\(appearance)") }
        if let contentSize { parts.append("content-size=\(contentSize)") }
        if let increaseContrast { parts.append("increase-contrast=\(increaseContrast)") }
        if let hardwareKeyboard { parts.append("hardware-keyboard=\(hardwareKeyboard)") }
        if let statusBar, !statusBar.isEmpty {
            parts.append("status-bar=[" + statusBar.keys.sorted().joined(separator: ",") + "]")
        }
        return parts.isEmpty ? "default" : parts.joined(separator: " ")
    }

    public func validate() throws {
        if locale != nil, language == nil {
            throw BenchmarkFailure.invalidTask(
                "device_state.locale needs a language; the CLI sets the locale as part of the language write"
            )
        }
        for key in (statusBar ?? [:]).keys where !Self.statusBarFlags.contains(key) {
            throw BenchmarkFailure.invalidTask(
                "device_state.status_bar has no flag '\(key)'. Valid keys: "
                    + Self.statusBarFlags.sorted().joined(separator: ", ")
            )
        }
    }

    public func applyCommands(udid: String) -> [ProcessCommand] {
        var commands: [ProcessCommand] = []
        if let orientation {
            commands.append(flowdeck(["simulator", "orientation", "set", orientation], udid))
        }
        if let language {
            var arguments = ["simulator", "language", "set", language]
            if let locale { arguments += ["--locale", locale] }
            commands.append(flowdeck(arguments, udid))
        }
        if let appearance {
            commands.append(flowdeck(["simulator", "appearance", "set", appearance], udid))
        }
        if let contentSize {
            commands.append(flowdeck(["simulator", "content-size", "set", contentSize], udid))
        }
        if let increaseContrast {
            commands.append(flowdeck(["simulator", "increase-contrast", "set", increaseContrast], udid))
        }
        if let hardwareKeyboard {
            commands.append(flowdeck(["simulator", "keyboard", "hardware", hardwareKeyboard], udid))
        }
        if let statusBar, !statusBar.isEmpty {
            // Sorted so the recorded command is the same on every run. An
            // unordered argv makes a grading step impossible to reproduce.
            var arguments = ["simulator", "status-bar", "override"]
            for key in statusBar.keys.sorted() {
                arguments += ["--\(key)", statusBar[key] ?? ""]
            }
            commands.append(flowdeck(arguments, udid))
        }
        return commands
    }

    public func resetCommands(udid: String) -> [ProcessCommand] {
        var commands: [ProcessCommand] = []
        if orientation != nil {
            commands.append(flowdeck(["simulator", "orientation", "set", Self.defaultOrientation], udid))
        }
        if language != nil {
            commands.append(flowdeck(["simulator", "language", "reset"], udid))
        }
        if appearance != nil {
            commands.append(flowdeck(["simulator", "appearance", "reset"], udid))
        }
        if contentSize != nil {
            commands.append(flowdeck(["simulator", "content-size", "reset"], udid))
        }
        if increaseContrast != nil {
            commands.append(flowdeck(["simulator", "increase-contrast", "reset"], udid))
        }
        if hardwareKeyboard != nil {
            commands.append(flowdeck(["simulator", "keyboard", "hardware", "on"], udid))
        }
        if let statusBar, !statusBar.isEmpty {
            commands.append(flowdeck(["simulator", "status-bar", "clear"], udid))
        }
        return commands
    }

    private func flowdeck(_ arguments: [String], _ udid: String) -> ProcessCommand {
        ProcessCommand(executable: "flowdeck", arguments: arguments + ["-S", udid])
    }
}

/// Applies a ``SimulatorDeviceState`` and puts it back afterwards.
public struct SimulatorDeviceStateApplier: Sendable {
    private let grader: String
    private let context: GradingContext

    public init(grader: String, context: GradingContext) {
        self.grader = grader
        self.context = context
    }

    /// Applies `state`, runs `body`, and resets the device whatever `body` did.
    ///
    /// A state that cannot be applied is a grader *failure*, not a FAIL: the
    /// task asked to be judged rotated, and judging it upright would answer a
    /// question nobody asked. Reset failures are not fatal — the simulator is
    /// deleted at the end of the run anyway — so they are recorded and dropped
    /// rather than masking the grade.
    public func withState<T>(
        _ state: SimulatorDeviceState,
        perform body: () async throws -> T
    ) async throws -> T {
        try state.validate()
        guard !state.isEmpty else { return try await body() }
        guard let udid = context.simulatorUDID else {
            throw BenchmarkFailure.graderFailure(
                grader: grader,
                message: "device_state needs a simulator, and this run has none. "
                    + "Declare environment.simulator on the task."
            )
        }

        for command in state.applyCommands(udid: udid) {
            let result = try await context.runRecorded(command, timeout: .seconds(180))
            guard result.exitCode == 0 else {
                throw BenchmarkFailure.graderFailure(
                    grader: grader,
                    message: "Could not put the simulator into the graded state "
                        + "(\(command.displayString)): \(result.standardError.trimmed())"
                )
            }
        }

        defer {
            let reset = state.resetCommands(udid: udid)
            Task { [context] in
                for command in reset {
                    _ = try? await context.runRecorded(command, timeout: .seconds(180))
                }
            }
        }
        return try await body()
    }
}

extension String {
    /// Trims and caps a captured stderr so a grader message stays readable.
    public func trimmed(limit: Int = 400) -> String {
        let text = trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count <= limit ? text : String(text.prefix(limit)) + "…"
    }
}
