import XCTest

final class FamiliarColdLaunchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testColdLaunchShowsOnboardingOrChatShell() {
        let app = XCUIApplication()
        app.launchArguments += ["-familiar.ui-testing", "1"]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        XCTAssertTrue(app.windows.firstMatch.exists)
    }
}
