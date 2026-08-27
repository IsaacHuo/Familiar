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

    @MainActor
    func testAssistantTurnVisualFixtureSelectionAndCollapsedSources() {
        let app = XCUIApplication()
        app.launchArguments += ["-familiar.ui-testing", "1", "-familiar.visual-fixture", "1"]
        app.launch()

        let fixtureIDs = [
            "loading", "reasoning", "search", "approval", "clarification", "task",
            "recommendation", "insight", "receipt", "failure", "sources"
        ]
        for id in fixtureIDs {
            XCTAssertTrue(
                app.descendants(matching: .any)["visual-fixture.\(id)"].waitForExistence(timeout: 5),
                "Missing fixture section: \(id)"
            )
        }

        XCTAssertTrue(app.descendants(matching: .any)["message.sources.disclosure"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["message.source.row.fixture-read"].exists)

        let improve = app.buttons["selection.action.improve"]
        XCTAssertTrue(improve.exists)
        improve.tap()
        XCTAssertTrue(app.descendants(matching: .any)["visual-fixture.composer"].value as? String != "")
        XCTAssertEqual(app.descendants(matching: .any)["visual-fixture.send-count"].value as? String, "0")
    }
}
