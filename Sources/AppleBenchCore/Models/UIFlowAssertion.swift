import Foundation

/// One deterministic claim about the screen after a UI flow has run.
///
/// Kept small on purpose. The grader's job is to answer a question a person
/// could answer by looking at the device, and to answer it the same way every
/// time — not to encode a test framework in YAML. Everything here is a pure
/// function over ``UIFlowSnapshot``, so a task's assertions can be exercised
/// without booting anything.
public struct UIFlowAssertion: Sendable, Codable, Equatable {
    /// Some element's label or value contains this text.
    public var text: String?
    /// No element's label or value contains this text.
    public var absent: String?
    /// These labels appear, and appear in this order reading down the screen.
    /// This is the ordering claim: sort, reorder, and insert-position defects
    /// are exactly "the right rows, in the wrong sequence".
    public var order: [String]?

    /// Addresses a single element for the geometric clauses below, by
    /// accessibility identifier or, failing that, by label.
    public var id: String?
    public var label: String?

    /// The addressed element's frame lies entirely within the window.
    public var insideWindow: Bool?
    /// The addressed element is at least this wide / tall, in points.
    public var minWidth: Int?
    public var minHeight: Int?
    /// The addressed element's frame does not intersect this other element's.
    public var notOverlapping: String?

    /// The device's physical orientation. Asserting it proves the graded state
    /// was actually applied, rather than grading an upright screen and calling
    /// it a rotation test.
    public var orientation: String?

    public init(
        text: String? = nil,
        absent: String? = nil,
        order: [String]? = nil,
        id: String? = nil,
        label: String? = nil,
        insideWindow: Bool? = nil,
        minWidth: Int? = nil,
        minHeight: Int? = nil,
        notOverlapping: String? = nil,
        orientation: String? = nil
    ) {
        self.text = text
        self.absent = absent
        self.order = order
        self.id = id
        self.label = label
        self.insideWindow = insideWindow
        self.minWidth = minWidth
        self.minHeight = minHeight
        self.notOverlapping = notOverlapping
        self.orientation = orientation
    }

    enum CodingKeys: String, CodingKey {
        case text, absent, order, id, label, orientation
        case insideWindow = "inside_window"
        case minWidth = "min_width"
        case minHeight = "min_height"
        case notOverlapping = "not_overlapping"
    }

    public func validate() throws {
        let hasClause = text != nil || absent != nil || order != nil || orientation != nil
            || insideWindow != nil || minWidth != nil || minHeight != nil || notOverlapping != nil
        guard hasClause else {
            throw BenchmarkFailure.invalidTask("A uiflow assertion states nothing")
        }
        let geometric = insideWindow != nil || minWidth != nil || minHeight != nil || notOverlapping != nil
        guard !geometric || id != nil || label != nil else {
            throw BenchmarkFailure.invalidTask(
                "A uiflow assertion about geometry needs an 'id' or 'label' to address an element"
            )
        }
    }

    /// Why this assertion did not hold, or `nil` when it did.
    public func failure(against snapshot: UIFlowSnapshot) -> String? {
        if let text, !snapshot.elements.contains(where: { $0.searchableText.contains(text) }) {
            return "no element on screen shows \"\(text)\""
        }
        if let absent, let found = snapshot.elements.first(where: { $0.searchableText.contains(absent) }) {
            return "\"\(absent)\" is on screen, in \"\(found.searchableText)\""
        }
        if let order, let failure = orderFailure(order, in: snapshot) {
            return failure
        }
        if let orientation, snapshot.orientation != orientation {
            return "the device is \(snapshot.orientation), not \(orientation)"
        }

        let needsElement = insideWindow != nil || minWidth != nil || minHeight != nil || notOverlapping != nil
        guard needsElement else { return nil }

        let address = id ?? label ?? "?"
        guard let element = snapshot.element(id: id, label: label) else {
            return "no element \"\(address)\" on screen"
        }
        if insideWindow == true {
            guard let root = snapshot.root else { return "the screen reported no elements to measure against" }
            if !root.contains(element.frame) {
                return "\"\(address)\" at \(describe(element.frame)) is outside the window "
                    + "\(describe(root))"
            }
        }
        if let minWidth, element.frame.width < minWidth {
            return "\"\(address)\" is \(element.frame.width)pt wide, less than \(minWidth)pt"
        }
        if let minHeight, element.frame.height < minHeight {
            return "\"\(address)\" is \(element.frame.height)pt tall, less than \(minHeight)pt"
        }
        if let notOverlapping {
            guard let other = snapshot.element(id: notOverlapping, label: notOverlapping) else {
                return "no element \"\(notOverlapping)\" on screen to compare against"
            }
            if element.frame.intersects(other.frame) {
                return "\"\(address)\" at \(describe(element.frame)) overlaps "
                    + "\"\(notOverlapping)\" at \(describe(other.frame))"
            }
        }
        return nil
    }

    /// Reading order is geometric — down the screen, then across. The order the
    /// accessibility walk happens to emit is an implementation detail of the
    /// tree; what a person sees is the layout.
    private func orderFailure(_ expected: [String], in snapshot: UIFlowSnapshot) -> String? {
        var positions: [(label: String, y: Int, x: Int)] = []
        for label in expected {
            guard let element = snapshot.elements.first(where: { $0.label == label })
                ?? snapshot.elements.first(where: { $0.searchableText.contains(label) })
            else {
                return "\"\(label)\" is not on screen, so the order cannot hold"
            }
            positions.append((label, element.frame.y, element.frame.x))
        }
        for index in 1..<max(positions.count, 1) {
            let previous = positions[index - 1]
            let current = positions[index]
            let inOrder = previous.y < current.y || (previous.y == current.y && previous.x < current.x)
            if !inOrder {
                return "\"\(current.label)\" comes before \"\(previous.label)\" on screen; "
                    + "expected \(expected.map { "\"\($0)\"" }.joined(separator: ", "))"
            }
        }
        return nil
    }

    private func describe(_ frame: UIFlowSnapshot.Frame) -> String {
        "(\(frame.x), \(frame.y)) \(frame.width)x\(frame.height)"
    }
}
