import XCTest

final class FamiliarTerminalUITests: XCTestCase {
    @MainActor func testProductionTerminalEntryRealInputInterruptExitAndRestart() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-familiar.ui-testing", "1", "-familiar.chat-testing", "1", "-AppleLanguages", "(en)"]
        app.launch()
        XCTAssertTrue(app.buttons["chat.more"].waitForExistence(timeout: 20))
        app.buttons["chat.more"].tap()
        XCTAssertTrue(app.buttons["chat.terminal"].waitForExistence(timeout: 5))
        app.buttons["chat.terminal"].tap()
        let start = app.buttons["terminal.startStop"]
        XCTAssertTrue(start.waitForExistence(timeout: 10)); start.tap()
        let status = app.staticTexts["terminal.status"]
        let running = NSPredicate(format: "label == %@", "Running")
        expectation(for: running, evaluatedWith: status); waitForExpectations(timeout: 90)
        func send(_ command: String) {
            let input = app.textFields["terminal.command"]
            input.tap(); input.typeText(command)
            app.buttons["terminal.send"].tap()
        }
        send("stty -echo; printf '\\033[32m%s%s\\033[0m\\n' FC_ UI_READY")
        let output = app.staticTexts["terminal.output"]
        expectation(for: NSPredicate(format: "value CONTAINS %@", "FC_UI_READY"), evaluatedWith: output)
        waitForExpectations(timeout: 15)
        send("sleep 30")
        app.buttons["Ctrl-C"].tap()
        send("printf '%s%s\\n' FC_ AFTER_INTERRUPT")
        expectation(for: NSPredicate(format: "value CONTAINS %@", "FC_AFTER_INTERRUPT"), evaluatedWith: output)
        waitForExpectations(timeout: 15)
        app.buttons["Ctrl-D"].tap()
        expectation(for: NSPredicate(format: "label == %@", "Exited (0)"), evaluatedWith: status)
        waitForExpectations(timeout: 15)
        start.tap()
        expectation(for: running, evaluatedWith: status); waitForExpectations(timeout: 15)
        send("printf '%s%s\\n' FC_ RESTARTED")
        expectation(for: NSPredicate(format: "value CONTAINS %@", "FC_RESTARTED"), evaluatedWith: output)
        waitForExpectations(timeout: 15)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "FC-production-interactive-terminal"; screenshot.lifetime = .keepAlways; add(screenshot)
        start.tap()
        expectation(for: NSPredicate(format: "label == %@", "Stopped"), evaluatedWith: status)
        waitForExpectations(timeout: 15)
    }
}
