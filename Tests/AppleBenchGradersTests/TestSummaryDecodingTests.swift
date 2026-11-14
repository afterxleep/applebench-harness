import Foundation
import Testing
@testable import AppleBenchGraders

@Suite("xcresult summary decoding")
struct TestSummaryDecodingTests {
    /// Shape captured from `xcrun xcresulttool get test-results summary`
    /// under Xcode 27 — note the numeric `testIdentifier`, which must not
    /// break decoding.
    @Test("Real Xcode summary JSON decodes")
    func realSummary() throws {
        let json = """
        {
          "environmentDescription" : "StateFixture · Built with macOS 26.5.1",
          "expectedFailures" : 0,
          "failedTests" : 1,
          "finishTime" : 1786182095.327,
          "passedTests" : 1,
          "result" : "Failed",
          "skippedTests" : 0,
          "startTime" : 1786182009.081,
          "testFailures" : [
            {
              "failureText" : "XCTAssertEqual failed: (\\"0\\") is not equal to (\\"3\\")",
              "targetName" : "StateFixtureTests",
              "testIdentifier" : 1,
              "testIdentifierString" : "CounterPersistenceTests/testCountSurvivesStoreRecreation()",
              "testName" : "testCountSurvivesStoreRecreation()"
            }
          ],
          "title" : "Test - StateFixture",
          "totalTestCount" : 2
        }
        """
        let summary = try JSONDecoder().decode(
            XcodebuildSupport.TestSummary.self,
            from: Data(json.utf8)
        )
        #expect(summary.totalTestCount == 2)
        #expect(summary.failedTests == 1)
        #expect(summary.passedTests == 1)
        #expect(summary.result == "Failed")
        #expect(summary.testFailures?.first?.testIdentifierString
            == "CounterPersistenceTests/testCountSurvivesStoreRecreation()")
    }
}
