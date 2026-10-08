import XCTest

final class FamiliarChatPresentationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    private func chat(_ prompt: String, accessibility: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-familiar.ui-testing", "1", "-familiar.chat-testing", "1", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if accessibility { app.launchArguments += ["-familiar.accessibility-testing"] }
        app.launch()
        let input = app.textViews["composer.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 15))
        input.tap()
        input.typeText(prompt)
        app.buttons["composer.send"].tap()
        return app
    }

    @MainActor
    func testShortReplyCompletesThroughProductionChat() {
        let app = chat("short")
        XCTAssertTrue(app.buttons["message.copy"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Reply complete."].waitForExistence(timeout: 15))
        XCTAssertEqual(app.webViews.matching(identifier: "markdown.webview").count, 1)
        let copy = app.buttons["message.copy"]
        copy.tap()
        // XCTest waits for the short acknowledgement animation before querying.
        // Its immediate/lifetime state is verified by confirmationLifetime.
        XCTAssertTrue(copy.waitForExistence(timeout: 3))
        let reset = NSPredicate(format: "label == %@", "Copy")
        expectation(for: reset, evaluatedWith: copy)
        waitForExpectations(timeout: 4)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "I1-short-production-chat"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor private func measureHistoryScrolling(count: Int) {
        let app = XCUIApplication()
        app.launchArguments = ["-familiar.ui-testing", "1", "-familiar.chat-testing", "1", "-familiar.history-count", String(count), "-AppleLanguages", "(en)"]
        app.launch()
        let timeline = app.scrollViews["chat.timeline"]
        XCTAssertTrue(timeline.waitForExistence(timeout: 120))
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        measure(metrics: [XCTOSSignpostMetric.scrollingAndDecelerationMetric, XCTMemoryMetric(application: app)], options: options) {
            // Avoid re-resolving the complete WebKit AX tree for every gesture.
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
        }
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "I8-history-\(count)-after-scrolling"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testFollowUpsUseReplyContentAndOnlyFillComposer() {
        let app = chat("markdown")
        let question = app.buttons["message.follow_up.0"]
        XCTAssertTrue(question.waitForExistence(timeout: 35))
        XCTAssertTrue(question.label.contains("Markdown report"))
        question.tap()
        let input = app.textViews["composer.input"]
        XCTAssertTrue((input.value as? String)?.contains("Markdown report") == true)
        XCTAssertTrue(app.buttons["message.copy"].exists)
        XCTAssertEqual(app.buttons["composer.send"].label, "Send")
    }

    @MainActor
    func testDiskBackedReplySurvivesRelaunchWithoutDuplicateOrRunningState() {
        let app = XCUIApplication()
        app.launchArguments = ["-familiar.ui-testing", "1", "-familiar.chat-testing", "1", "-familiar.disk-testing", "1",
            "-familiar.test-store-id", "fc-" + UUID().uuidString, "-AppleLanguages", "(en)"]
        app.launch()
        let input = app.textViews["composer.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 15))
        input.tap(); input.typeText("FC persisted reply")
        app.buttons["composer.send"].tap()
        XCTAssertTrue(app.buttons["message.copy"].waitForExistence(timeout: 35))
        XCTAssertTrue(app.buttons["message.follow_up.0"].waitForExistence(timeout: 15))
        let savedSuggestion = app.buttons["message.follow_up.0"].label
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["message.copy"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.buttons["message.follow_up.0"].label, savedSuggestion)
        let drawer = app.buttons["chat.history.open"]
        XCTAssertTrue(drawer.waitForExistence(timeout: 15)); drawer.tap()
        let chat = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@",
            "chat.history.row.", "FC persisted reply")).firstMatch
        if !chat.waitForExistence(timeout: 4) {
            let expand = app.buttons["Expand Project"].firstMatch
            if expand.exists { expand.tap() }
        }
        XCTAssertTrue(chat.waitForExistence(timeout: 10)); chat.tap()
        XCTAssertTrue(app.buttons["message.copy"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.buttons.matching(identifier: "message.copy").count, 1)
        XCTAssertEqual(app.buttons["composer.send"].label, "Send")
        let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        capture.name = "FC-disk-relaunch"; capture.lifetime = .keepAlways; add(capture)
    }

    @MainActor func testHistory100RealGestureScrollingMetrics() { measureHistoryScrolling(count: 100) }
    @MainActor func testHistory300RealGestureScrollingMetrics() { measureHistoryScrolling(count: 300) }

    @MainActor
    func testReducedMotionAndLargeTypeCompleteInProductionChat() {
        let app = chat("short", accessibility: true)
        XCTAssertTrue(app.buttons["message.copy"].waitForExistence(timeout: 25))
        XCTAssertGreaterThanOrEqual(app.buttons["composer.send"].frame.width, 44)
        XCTAssertGreaterThanOrEqual(app.buttons["composer.send"].frame.height, 44)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "I8-reduced-motion-large-type"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testLongReplyCanBeStoppedAndRetainsContext() {
        let app = chat("long")
        let stop = app.buttons["composer.send"]
        let stopLabel = NSPredicate(format: "label == %@", "Stop generating")
        expectation(for: stopLabel, evaluatedWith: stop)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 10))
        stop.tap()
        let sendLabel = NSPredicate(format: "label == %@", "Send")
        expectation(for: sendLabel, evaluatedWith: stop)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(app.webViews.firstMatch.exists)
        XCTAssertFalse(app.buttons["message.copy"].exists)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "I1-cancel-retains-incomplete-text"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testInterruptedProviderRetainsIncompleteTextAndDoesNotOfferCopyAsComplete() {
        let app = chat("error")
        if app.alerts.firstMatch.waitForExistence(timeout: 3) { app.alerts.buttons["OK"].tap() }
        XCTAssertTrue(app.staticTexts["This content is incomplete"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.webViews["markdown.webview"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["message.copy"].exists)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "I1-error-retains-context"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testReadingStopsFollowingAndReturnRestoresIt() {
        let app = chat("long")
        let timeline = app.scrollViews["chat.timeline"]
        XCTAssertTrue(timeline.waitForExistence(timeout: 10))
        XCTAssertTrue(app.webViews["markdown.webview"].waitForExistence(timeout: 15))
        timeline.swipeDown(velocity: .slow)
        let latest = app.buttons["chat.returnToLatest"]
        XCTAssertTrue(latest.waitForExistence(timeout: 10))
        let before = app.webViews["markdown.webview"].frame.minY
        Thread.sleep(forTimeInterval: 0.6)
        let after = app.webViews["markdown.webview"].frame.minY
        XCTAssertEqual(before, after, accuracy: 2)
        // A larger Composer/keyboard must retain the same reading position.
        app.textViews["composer.input"].tap()
        app.textViews["composer.input"].typeText("A draft\nwith several\nlines")
        XCTAssertTrue(latest.exists)
        latest.tap()
        let hidden = NSPredicate(format: "exists == false")
        expectation(for: hidden, evaluatedWith: latest)
        waitForExpectations(timeout: 10)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "I2-return-to-latest"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testToolActivityExpandsAndOpensTechnicalDetail() {
        let app = chat("tools")
        XCTAssertTrue(app.buttons["message.copy"].waitForExistence(timeout: 20))
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "runtime.toggle.")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let detail = app.descendants(matching: .any)["runtime.details"]
        XCTAssertTrue(detail.waitForExistence(timeout: 10))
        detail.tap()
        XCTAssertTrue(app.descendants(matching: .any)["runtime.detail"].waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "I3-native-runtime-detail"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testApprovalCreatesOneOpenableFileAndReceipt() {
        let app = chat("file")
        let approve = app.buttons["approval.confirm"]
        XCTAssertTrue(approve.waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "file.open.")).firstMatch.exists)
        approve.tap()
        let file = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "file.open.")).firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["message.copy"].waitForExistence(timeout: 20))
        XCTAssertFalse(approve.exists)
        file.tap()
        XCTAssertTrue(app.navigationBars["Presentation report.md"].waitForExistence(timeout: 10))
        app.buttons["Done"].tap()
        XCTAssertTrue(file.waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "I3-file-and-associated-receipt"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testMarkdownCodeTableAndDiagramCompleteInProductionChat() {
        let app = chat("markdown")
        XCTAssertTrue(app.buttons["message.copy"].waitForExistence(timeout: 20))
        let web = app.webViews["markdown.webview"]
        XCTAssertTrue(web.waitForExistence(timeout: 15))
        XCTAssertTrue(web.buttons["Copy"].waitForExistence(timeout: 20))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "I5-markdown-code-table-diagram"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testProjectChatPushReturnsToOriginalProject() {
        let app = chat("short")
        XCTAssertTrue(app.buttons["message.copy"].waitForExistence(timeout: 20))
        app.buttons["chat.projects"].tap()
        app.buttons["All Projects"].tap()
        let daily = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "project.open.")).firstMatch
        XCTAssertTrue(daily.waitForExistence(timeout: 10))
        daily.tap()
        let newChat = app.buttons["project.newChat"]
        XCTAssertTrue(newChat.waitForExistence(timeout: 10))
        newChat.tap()
        XCTAssertTrue(app.textViews["composer.input"].waitForExistence(timeout: 10))
        let child = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        child.name = "I6-project-chat-child"
        child.lifetime = .keepAlways
        add(child)
        app.buttons["chat.more"].tap()
        app.buttons["Browse Chat Files"].tap()
        XCTAssertTrue(app.navigationBars["Browse Chat Files"].waitForExistence(timeout: 10))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.textViews["composer.input"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars.buttons.firstMatch.exists)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(newChat.waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "I6-project-chat-return"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
