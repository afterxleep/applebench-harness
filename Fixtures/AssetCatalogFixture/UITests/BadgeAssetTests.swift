import XCTest

/// Benchmark verification: the badge artwork must actually resolve at runtime.
final class BadgeAssetTests: XCTestCase {
    @MainActor
    func testBadgeArtworkResolves() {
        let app = XCUIApplication()
        app.launch()

        let status = app.staticTexts["badge-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 15), "The certification screen must be on screen")
        XCTAssertEqual(
            status.label, "Badge loaded",
            "The badge image must resolve from the app's asset catalog"
        )
        XCTAssertTrue(app.images["badge"].exists, "The badge must be shown")
    }
}
