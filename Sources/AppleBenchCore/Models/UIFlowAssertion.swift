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
    /// An ISO calendar day that must be shown using any standard date style
    /// for `locale`. This grades the date a user reads, not one exact string.
    public var localizedDate: String?
    public var locale: String?
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
    /// The addressed element sits entirely above this other element.
    ///
    /// The claim keyboard avoidance actually makes. A field covered by the
    /// software keyboard has not left the window — the keyboard is drawn over
    /// the top and the frame never moves — so `inside_window` cannot see it.
    /// What a working layout guarantees is that the control stays clear.
    public var above: String?

    /// The device's physical orientation. Asserting it proves the graded state
    /// was actually applied, rather than grading an upright screen and calling
    /// it a rotation test.
    public var orientation: String?

    public init(
        text: String? = nil,
        absent: String? = nil,
        localizedDate: String? = nil,
        locale: String? = nil,
        order: [String]? = nil,
        id: String? = nil,
        label: String? = nil,
        insideWindow: Bool? = nil,
        minWidth: Int? = nil,
        minHeight: Int? = nil,
        notOverlapping: String? = nil,
        above: String? = nil,
        orientation: String? = nil
    ) {
        self.text = text
        self.absent = absent
        self.localizedDate = localizedDate
        self.locale = locale
        self.order = order
        self.id = id
        self.label = label
        self.insideWindow = insideWindow
        self.minWidth = minWidth
        self.minHeight = minHeight
        self.notOverlapping = notOverlapping
        self.above = above
        self.orientation = orientation
    }

    enum CodingKeys: String, CodingKey {
        case text, absent, locale, order, id, label, orientation, above
        case localizedDate = "localized_date"
        case insideWindow = "inside_window"
        case minWidth = "min_width"
        case minHeight = "min_height"
        case notOverlapping = "not_overlapping"
    }

    public func validate() throws {
        let hasClause = text != nil || absent != nil || localizedDate != nil
            || order != nil || orientation != nil
            || insideWindow != nil || minWidth != nil || minHeight != nil || notOverlapping != nil
            || above != nil
        guard hasClause else {
            throw BenchmarkFailure.invalidTask("A uiflow assertion states nothing")
        }
        if let localizedDate {
            guard let locale, !locale.isEmpty else {
                throw BenchmarkFailure.invalidTask(
                    "A localized_date assertion needs a locale"
                )
            }
            guard Self.isoDate(localizedDate) != nil else {
                throw BenchmarkFailure.invalidTask(
                    "uiflow localized_date '\(localizedDate)' is not YYYY-MM-DD"
                )
            }
        } else if locale != nil {
            throw BenchmarkFailure.invalidTask(
                "A uiflow assertion locale is only meaningful with localized_date"
            )
        }
        let geometric = insideWindow != nil || minWidth != nil || minHeight != nil
            || notOverlapping != nil || above != nil
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
        if let localizedDate, let locale,
           let failure = localizedDateFailure(
               localizedDate,
               locale: locale,
               snapshot: snapshot
           ) {
            return failure
        }
        if let order, let failure = orderFailure(order, in: snapshot) {
            return failure
        }
        if let orientation, snapshot.orientation != orientation {
            return "the device is \(snapshot.orientation), not \(orientation)"
        }

        let needsElement = insideWindow != nil || minWidth != nil || minHeight != nil
            || notOverlapping != nil || above != nil
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
        if let above {
            guard let other = snapshot.element(id: above, label: above) else {
                return "no element \"\(above)\" on screen to sit above"
            }
            if element.frame.maxY > other.frame.y {
                return "\"\(address)\" at \(describe(element.frame)) is not clear of "
                    + "\"\(above)\" at \(describe(other.frame))"
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

    private func localizedDateFailure(
        _ iso: String,
        locale: String,
        snapshot: UIFlowSnapshot
    ) -> String? {
        guard let expected = Self.isoDate(iso) else {
            return "localized date \"\(iso)\" is not a valid calendar day"
        }
        let candidates: [UIFlowSnapshot.Element]
        if id != nil || label != nil {
            guard let element = snapshot.element(id: id, label: label) else {
                return "no element \"\(id ?? label ?? "?")\" on screen"
            }
            candidates = [element]
        } else {
            candidates = snapshot.elements
        }

        let calendar = Self.gregorianUTC
        let styles: [DateFormatter.Style] = [.short, .medium, .long, .full]
        let presentationLocales = Self.presentationLocales(for: locale)
        for candidate in candidates {
            for text in [candidate.label, candidate.value].compactMap({ $0 }) {
                for presentationLocale in presentationLocales {
                    for style in styles {
                        let formatter = DateFormatter()
                        formatter.locale = presentationLocale
                        formatter.calendar = calendar
                        formatter.timeZone = calendar.timeZone
                        formatter.dateStyle = style
                        formatter.timeStyle = .none
                        formatter.isLenient = false
                        guard let date = formatter.date(from: text) else { continue }
                        let components = calendar.dateComponents([.year, .month, .day], from: date)
                        if components == expected { return nil }
                    }
                }
            }
        }
        return "no addressed element shows calendar day \"\(iso)\" in locale \"\(locale)\""
    }

    /// An app without a localization for the device language keeps its base
    /// language while adopting the user's region. Foundation then formats a
    /// German-region date with an English month name (for example,
    /// "4. Mar 2026"). Keep the requested region when accepting that standard
    /// presentation so numeric day/month order cannot drift to another region.
    private static func presentationLocales(for identifier: String) -> [Locale] {
        let requested = Locale(identifier: identifier)
        guard let region = requested.region?.identifier else { return [requested] }
        let baseLanguage = Locale(identifier: "en_\(region)")
        guard baseLanguage.identifier != requested.identifier else { return [requested] }
        return [requested, baseLanguage]
    }

    private static var gregorianUTC: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func isoDate(_ text: String) -> DateComponents? {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else { return nil }
        var components = DateComponents()
        components.calendar = gregorianUTC
        components.timeZone = gregorianUTC.timeZone
        components.year = year
        components.month = month
        components.day = day
        guard components.date != nil else { return nil }
        return DateComponents(year: year, month: month, day: day)
    }
}
