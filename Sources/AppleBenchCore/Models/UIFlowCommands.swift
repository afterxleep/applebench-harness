import Foundation

/// One privacy permission change applied before the app is launched.
///
/// A denied permission is not an edge case, it is a state a large share of
/// users are permanently in, and the path through it is the one nobody
/// exercises — the app was written by someone who tapped Allow.
public struct UIFlowPrivacyChange: Sendable, Codable, Equatable {
    /// `grant`, `revoke`, or `reset`.
    public var action: String
    /// A `simctl privacy` service: `photos`, `camera`, `location`,
    /// `contacts`, `microphone`, `calendar`, `all`, …
    public var service: String

    public init(action: String, service: String) {
        self.action = action
        self.service = service
    }
}

/// A drag between two screen points, in points, as read off the accessibility
/// tree or a FlowDeck screenshot — never scaled by @2x/@3x.
public struct UIFlowGesture: Sendable, Codable, Equatable {
    /// `"x,y"` where the finger goes down.
    public var from: String
    /// `"x,y"` where it lifts.
    public var to: String
    /// Seconds to hold before moving. Drag-to-reorder does not engage without
    /// one; a plain swipe does not want one.
    public var hold: Double?
    public var duration: Double?

    public init(from: String, to: String, hold: Double? = nil, duration: Double? = nil) {
        self.from = from
        self.to = to
        self.hold = hold
        self.duration = duration
    }
}

/// The FlowDeck invocations a UI flow needs beyond the device state itself.
///
/// Separated from the grader so the argv is a pure function that can be pinned
/// by a test. A grader that builds command lines inline can only be checked by
/// running a simulator.
public enum UIFlowCommands {
    static let privacyActions: Set<String> = ["grant", "revoke", "reset"]

    public static func privacy(
        _ change: UIFlowPrivacyChange,
        bundleIdentifier: String,
        udid: String
    ) -> ProcessCommand {
        // `reset` may target every service at once and takes no bundle id in
        // that form; grant and revoke always name the app.
        var arguments = ["simulator", "privacy", change.action, change.service]
        if !(change.action == "reset" && change.service == "all") {
            arguments += ["--bundle-id", bundleIdentifier]
        }
        return flowdeck(arguments, udid)
    }

    public static func push(payload: String, bundleIdentifier: String, udid: String) -> ProcessCommand {
        flowdeck(["simulator", "push", payload, "--bundle-id", bundleIdentifier], udid)
    }

    /// Wipes the app's container, so the next launch is a first run.
    public static func clearState(bundleIdentifier: String, udid: String) -> ProcessCommand {
        flowdeck(["ui", "simulator", "clear-state", "--bundle-id", bundleIdentifier], udid)
    }

    public static func openURL(_ url: String, udid: String) -> ProcessCommand {
        flowdeck(["ui", "simulator", "open-url", url], udid)
    }

    public static func memoryWarning(udid: String) -> ProcessCommand {
        flowdeck(["simulator", "memory-warning"], udid)
    }

    public static func button(_ button: String, udid: String) -> ProcessCommand {
        flowdeck(["simulator", "button", button], udid)
    }

    /// A precise drag between two points.
    ///
    /// The batch `swipe` action only takes a direction, which is enough to
    /// scroll and not enough to act on a particular row. Row-level gestures —
    /// swipe-to-delete, and drag-to-reorder, which only engages after a long
    /// press — need real endpoints and a hold.
    public static func swipe(_ gesture: UIFlowGesture, udid: String) -> ProcessCommand {
        var arguments = [
            "ui", "simulator", "swipe",
            "--from", gesture.from,
            "--to", gesture.to,
        ]
        if let hold = gesture.hold { arguments += ["--hold", String(hold)] }
        if let duration = gesture.duration { arguments += ["--duration", String(duration)] }
        return flowdeck(arguments, udid)
    }

    public static func validate(privacy: [UIFlowPrivacyChange]) throws {
        for change in privacy where !privacyActions.contains(change.action) {
            throw BenchmarkFailure.invalidTask(
                "uiflow privacy has no action '\(change.action)'. Valid: "
                    + privacyActions.sorted().joined(separator: ", ")
            )
        }
    }

    public static func validate(gestures: [UIFlowGesture]) throws {
        for gesture in gestures {
            for point in [gesture.from, gesture.to] where !isPoint(point) {
                throw BenchmarkFailure.invalidTask(
                    "uiflow gesture point '\(point)' is not an x,y pair in points"
                )
            }
        }
    }

    static func isPoint(_ text: String) -> Bool {
        let parts = text.split(separator: ",")
        return parts.count == 2 && parts.allSatisfy { Int($0.trimmingCharacters(in: .whitespaces)) != nil }
    }

    private static func flowdeck(_ arguments: [String], _ udid: String) -> ProcessCommand {
        ProcessCommand(executable: "flowdeck", arguments: arguments + ["-S", udid])
    }
}
