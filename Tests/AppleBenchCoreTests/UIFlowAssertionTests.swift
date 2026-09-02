import Foundation
import Testing
@testable import AppleBenchCore

@Suite("UI flow assertions")
struct UIFlowAssertionTests {
    /// A three-row list, laid out top to bottom, inside a 390x844 root.
    private func rows(_ labels: [String], startY: Int = 100, step: Int = 60) -> UIFlowSnapshot {
        var elements: [UIFlowSnapshot.Element] = [
            .init(role: "window", id: nil, label: nil, value: nil, frame: .init(x: 0, y: 0, width: 390, height: 844))
        ]
        for (index, label) in labels.enumerated() {
            elements.append(.init(
                role: "staticText",
                id: "row-\(index)",
                label: label,
                value: nil,
                frame: .init(x: 16, y: startY + index * step, width: 200, height: 44)
            ))
        }
        return UIFlowSnapshot(elements: elements, orientation: "portrait")
    }

    @Test("Text passes when any element's label carries it")
    func textPresent() {
        let snapshot = rows(["Alpha", "Bravo"])
        #expect(UIFlowAssertion(text: "Alpha").failure(against: snapshot) == nil)
        #expect(UIFlowAssertion(text: "Zulu").failure(against: snapshot) != nil)
    }

    @Test("Text also matches an element's value, not only its label")
    func textMatchesValue() {
        let snapshot = UIFlowSnapshot(
            elements: [.init(role: "textField", id: "total", label: "Total", value: "42", frame: .init(x: 0, y: 0, width: 10, height: 10))],
            orientation: "portrait"
        )
        #expect(UIFlowAssertion(text: "42").failure(against: snapshot) == nil)
    }

    @Test("Absent fails when the text is on screen")
    func textAbsent() {
        let snapshot = rows(["Alpha", "Error: could not load"])
        #expect(UIFlowAssertion(absent: "Error").failure(against: snapshot) != nil)
        #expect(UIFlowAssertion(absent: "Warning").failure(against: snapshot) == nil)
    }

    @Test("Order reads the rows top to bottom, not the order the tree happened to list them")
    func orderIsGeometric() {
        // The accessibility tree's own ordering is an implementation detail of
        // the walk. What a user sees is the geometry, so that is what is graded.
        var snapshot = rows(["Charlie", "Alpha", "Bravo"])
        snapshot.elements.reverse()

        #expect(UIFlowAssertion(order: ["Charlie", "Alpha", "Bravo"]).failure(against: snapshot) == nil)
        #expect(UIFlowAssertion(order: ["Alpha", "Bravo", "Charlie"]).failure(against: snapshot) != nil)
    }

    @Test("Order names the first pair that is out of sequence")
    func orderFailureIsSpecific() {
        let snapshot = rows(["Alpha", "Charlie", "Bravo"])
        let failure = UIFlowAssertion(order: ["Alpha", "Bravo", "Charlie"]).failure(against: snapshot)
        let message = try! #require(failure)
        #expect(message.contains("Bravo"))
        #expect(message.contains("Charlie"))
    }

    @Test("Order fails when one of the labels is not on screen at all")
    func orderRequiresEveryLabel() {
        let snapshot = rows(["Alpha", "Bravo"])
        let failure = UIFlowAssertion(order: ["Alpha", "Bravo", "Charlie"]).failure(against: snapshot)
        #expect(try! #require(failure).contains("Charlie"))
    }

    @Test("Ties on y are broken by x, so a row of side-by-side controls still has an order")
    func orderBreaksTiesHorizontally() {
        let snapshot = UIFlowSnapshot(
            elements: [
                .init(role: "window", id: nil, label: nil, value: nil, frame: .init(x: 0, y: 0, width: 390, height: 844)),
                .init(role: "button", id: "b", label: "Right", value: nil, frame: .init(x: 200, y: 100, width: 80, height: 40)),
                .init(role: "button", id: "a", label: "Left", value: nil, frame: .init(x: 20, y: 100, width: 80, height: 40)),
            ],
            orientation: "portrait"
        )
        #expect(UIFlowAssertion(order: ["Left", "Right"]).failure(against: snapshot) == nil)
        #expect(UIFlowAssertion(order: ["Right", "Left"]).failure(against: snapshot) != nil)
    }

    @Test("Inside-window catches an element pushed off the edge")
    func insideWindow() {
        var snapshot = rows(["Alpha"])
        #expect(UIFlowAssertion(id: "row-0", insideWindow: true).failure(against: snapshot) == nil)

        snapshot.elements[1].frame.x = 300 // 300 + 200 > 390
        #expect(UIFlowAssertion(id: "row-0", insideWindow: true).failure(against: snapshot) != nil)
    }

    @Test("A minimum size catches a tap target too small to hit")
    func minimumSize() {
        var snapshot = rows(["Alpha"])
        #expect(UIFlowAssertion(id: "row-0", minWidth: 44, minHeight: 44).failure(against: snapshot) == nil)

        snapshot.elements[1].frame.height = 20
        let failure = UIFlowAssertion(id: "row-0", minWidth: 44, minHeight: 44).failure(against: snapshot)
        #expect(try! #require(failure).contains("20"))
    }

    @Test("Non-overlap catches two elements drawn on top of each other")
    func notOverlapping() {
        var snapshot = rows(["Alpha", "Bravo"])
        #expect(UIFlowAssertion(id: "row-0", notOverlapping: "row-1").failure(against: snapshot) == nil)

        snapshot.elements[2].frame.y = 110 // now inside row-0's 100...140
        #expect(UIFlowAssertion(id: "row-0", notOverlapping: "row-1").failure(against: snapshot) != nil)
    }

    @Test("Orientation asserts the state the device was actually in")
    func orientation() {
        // Proves the device_state actually took effect; a rotation that silently
        // failed would otherwise grade as a passing portrait layout.
        let snapshot = UIFlowSnapshot(elements: [], orientation: "landscape-left")
        #expect(UIFlowAssertion(orientation: "landscape-left").failure(against: snapshot) == nil)
        #expect(UIFlowAssertion(orientation: "portrait").failure(against: snapshot) != nil)
    }

    @Test("An assertion naming a missing element fails rather than passing vacuously")
    func missingElementFails() {
        let snapshot = rows(["Alpha"])
        #expect(UIFlowAssertion(id: "nope", insideWindow: true).failure(against: snapshot) != nil)
        #expect(UIFlowAssertion(id: "nope", minWidth: 44).failure(against: snapshot) != nil)
    }

    @Test("An assertion with no clause is rejected as an authoring mistake")
    func emptyAssertionIsInvalid() {
        #expect(throws: BenchmarkFailure.self) { try UIFlowAssertion().validate() }
        #expect(throws: Never.self) { try UIFlowAssertion(text: "x").validate() }
    }

    @Test("An element may be addressed by label when it has no identifier")
    func addressableByLabel() {
        let snapshot = rows(["Alpha"])
        #expect(UIFlowAssertion(label: "Alpha", insideWindow: true).failure(against: snapshot) == nil)
    }
}

@Suite("UI flow snapshot parsing")
struct UIFlowSnapshotParsingTests {
    @Test("Parses the tree and orientation out of a batch response")
    func parsesBatchResponse() throws {
        let json = """
        {
          "success": true,
          "type": "ui_batch",
          "steps": [{"index": 0, "action": "tap", "success": true}],
          "final": {
            "accessibility": {
              "orientation": "landscape-left",
              "tree": [
                {"role": "window", "frame": {"x": 0, "y": 0, "width": 844, "height": 390},
                 "center": {"x": 422, "y": 195}, "enabled": true, "visible": true},
                {"role": "staticText", "id": "price", "label": "Total", "value": "£4.00",
                 "frame": {"x": 700, "y": 40, "width": 120, "height": 20},
                 "center": {"x": 760, "y": 50}, "enabled": true, "visible": true}
              ]
            }
          }
        }
        """
        let response = try UIFlowBatchResponse(json: Data(json.utf8))
        #expect(response.stepFailure == nil)
        #expect(response.snapshot.orientation == "landscape-left")
        #expect(response.snapshot.elements.count == 2)
        #expect(response.snapshot.elements[1].value == "£4.00")
    }

    @Test("A failed step is reported with its index and the CLI's own error")
    func reportsStepFailure() throws {
        let json = """
        {
          "success": false,
          "type": "ui_batch",
          "steps": [
            {"index": 0, "action": "tap", "success": true},
            {"index": 1, "action": "assert", "success": false, "error": "text not found: Ascending"}
          ],
          "final": {"accessibility": {"orientation": "portrait", "tree": []}}
        }
        """
        let response = try UIFlowBatchResponse(json: Data(json.utf8))
        let failure = try #require(response.stepFailure)
        #expect(failure.contains("step 1"))
        #expect(failure.contains("assert"))
        #expect(failure.contains("Ascending"))
    }

    @Test("A response that is not the expected shape is an error, never a silent pass")
    func malformedResponseThrows() {
        #expect(throws: BenchmarkFailure.self) {
            _ = try UIFlowBatchResponse(json: Data("not json".utf8))
        }
        #expect(throws: BenchmarkFailure.self) {
            _ = try UIFlowBatchResponse(json: Data(#"{"success":true}"#.utf8))
        }
    }
}
