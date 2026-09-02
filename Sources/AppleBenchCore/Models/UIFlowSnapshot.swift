import Foundation

/// The screen, as the accessibility tree reports it, flattened.
///
/// This is the only thing the `uiflow` grader judges. It is deliberately small:
/// a role, an optional identifier, label and value, and a frame in points. That
/// is enough to answer every question the set needs — is this text on screen,
/// are these rows in this order, is this control still inside the window, is it
/// big enough to hit, do these two overlap — and it keeps the grader a pure
/// function over data that can be tested without a simulator.
public struct UIFlowSnapshot: Sendable, Equatable {
    public struct Frame: Sendable, Equatable {
        public var x: Int
        public var y: Int
        public var width: Int
        public var height: Int

        public init(x: Int, y: Int, width: Int, height: Int) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }

        var maxX: Int { x + width }
        var maxY: Int { y + height }

        func contains(_ other: Frame) -> Bool {
            other.x >= x && other.y >= y && other.maxX <= maxX && other.maxY <= maxY
        }

        func intersects(_ other: Frame) -> Bool {
            x < other.maxX && other.x < maxX && y < other.maxY && other.y < maxY
        }
    }

    public struct Element: Sendable, Equatable {
        public var role: String
        public var id: String?
        public var label: String?
        public var value: String?
        public var frame: Frame

        public init(role: String, id: String?, label: String?, value: String?, frame: Frame) {
            self.role = role
            self.id = id
            self.label = label
            self.value = value
            self.frame = frame
        }

        /// The text a reader would see for this element, for `text` matching.
        var searchableText: String {
            [label, value].compactMap { $0 }.joined(separator: " ")
        }
    }

    public var elements: [Element]
    /// The device's physical orientation, as FlowDeck detected it.
    public var orientation: String

    public init(elements: [Element], orientation: String) {
        self.elements = elements
        self.orientation = orientation
    }

    /// The largest element, treated as the window for containment checks. Using
    /// the biggest frame rather than looking for a `window` role keeps this
    /// working across the roles different iOS versions report for the root.
    var root: Frame? {
        elements.map(\.frame).max { ($0.width * $0.height) < ($1.width * $1.height) }
    }

    /// Addresses one element by identifier, then label, then role.
    ///
    /// Role is the fallback because some things on screen have neither of the
    /// first two — the software keyboard carries no identifier and no label,
    /// and it is exactly what a keyboard-avoidance claim needs to name.
    func element(id: String?, label: String?) -> Element? {
        if let id, let match = elements.first(where: { $0.id == id }) { return match }
        if let label, let match = elements.first(where: { $0.label == label }) { return match }
        let wanted = id ?? label
        if let wanted { return elements.first { $0.role.caseInsensitiveCompare(wanted) == .orderedSame } }
        return nil
    }
}

/// The `flowdeck ui simulator batch --json` envelope, reduced to what grading needs.
public struct UIFlowBatchResponse: Sendable {
    public let snapshot: UIFlowSnapshot
    /// The first step the CLI could not complete, already formatted. `nil` when
    /// every step ran.
    public let stepFailure: String?

    public init(json data: Data) throws {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BenchmarkFailure.graderFailure(
                grader: "uiflow",
                message: "The UI flow returned output that is not JSON. "
                    + String(decoding: data.prefix(400), as: UTF8.self)
            )
        }
        guard let final = root["final"] as? [String: Any],
              let accessibility = final["accessibility"] as? [String: Any],
              let tree = accessibility["tree"] as? [[String: Any]]
        else {
            throw BenchmarkFailure.graderFailure(
                grader: "uiflow",
                message: "The UI flow response carried no accessibility tree. Keys: "
                    + root.keys.sorted().joined(separator: ", ")
            )
        }

        var elements: [UIFlowSnapshot.Element] = []
        for entry in tree {
            let frame = entry["frame"] as? [String: Any] ?? [:]
            elements.append(UIFlowSnapshot.Element(
                role: entry["role"] as? String ?? "",
                id: entry["id"] as? String,
                label: entry["label"] as? String,
                value: entry["value"] as? String,
                frame: .init(
                    x: frame["x"] as? Int ?? 0,
                    y: frame["y"] as? Int ?? 0,
                    width: frame["width"] as? Int ?? 0,
                    height: frame["height"] as? Int ?? 0
                )
            ))
        }
        snapshot = UIFlowSnapshot(
            elements: elements,
            orientation: accessibility["orientation"] as? String ?? "unknown"
        )

        var failure: String?
        for step in (root["steps"] as? [[String: Any]] ?? []) where (step["success"] as? Bool) == false {
            let index = step["index"] as? Int ?? -1
            let action = step["action"] as? String ?? "?"
            let error = step["error"] as? String ?? "no reason given"
            failure = "step \(index) (\(action)) failed: \(error)"
            break
        }
        stepFailure = failure
    }
}
