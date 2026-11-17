import XCTest

/// Asserts that rapid taps on the Increment button always advance the
/// counter by the number of taps.
final class StateUITests: XCTestCase {
    func testRapidTapsIncrementReliably() throws {
        let app = XCUIApplication()
        app.launch()

        let button = app.buttons["increment"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))

        for _ in 0..<10 { button.tap() }
        // After ten taps the count must be exactly 10.
        let countText = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Count:'")).firstMatch
        XCTAssertTrue(countText.waitForExistence(timeout: 2))
        XCTAssertEqual(countText.label, "Count: 10")
    }

    func testPlusFiveAdvancesByExactlyFive() throws {
        let app = XCUIApplication()
        app.launch()

        let goDetail = app.buttons["goDetail"]
        XCTAssertTrue(goDetail.waitForExistence(timeout: 5))
        goDetail.tap()

        let plusFive = app.buttons["plusFive"]
        XCTAssertTrue(plusFive.waitForExistence(timeout: 5))
        plusFive.tap()

        let countText = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Count:'")).firstMatch
        XCTAssertTrue(countText.waitForExistence(timeout: 2))
        XCTAssertEqual(countText.label, "Count: 5")
    }
}
