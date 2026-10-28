import XCTest

final class FamiliarChatNavigationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor private func launch(appearance: String = "light", large: Bool = false, storeID: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-familiar.ui-testing", "1", "-familiar.chat-testing", "1", "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US", "-familiar.appearance.v1", appearance]
        if large { app.launchArguments += ["-familiar.accessibility-testing"] }
        if let storeID { app.launchArguments += ["-familiar.disk-testing", "1", "-familiar.test-store-id", storeID] }
        app.launch()
        XCTAssertTrue(app.buttons["chats.new"].waitForExistence(timeout: 20))
        return app
    }

    @MainActor private func back(_ app: XCUIApplication) {
        if app.buttons["chat.back"].exists { app.buttons["chat.back"].tap() }
        else { app.navigationBars.buttons.firstMatch.tap() }
    }

    @MainActor func testReviewNewConversationButtonAndKeyboardRepeatedly() {
        let app = launch()
        defer { XCUIDevice.shared.orientation = .portrait }
        for index in 0..<3 {
            XCTAssertTrue(app.buttons["chats.new"].waitForExistence(timeout: 10))
            app.buttons["chats.new"].tap()
            let input = app.textViews["composer.input"]
            XCTAssertTrue(input.waitForExistence(timeout: 10))
            input.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
            if index == 2 {
                let draft = "Review draft\nSecond line"
                input.typeText(draft)
                XCTAssertEqual(input.value as? String, draft)
                XCUIDevice.shared.orientation = .landscapeLeft
                XCTAssertTrue(input.waitForExistence(timeout: 5))
                XCTAssertEqual(input.value as? String, draft)
                XCUIDevice.shared.orientation = .portrait
            }
            back(app)
            XCTAssertTrue(app.buttons["chats.new"].waitForExistence(timeout: 10))
            XCTAssertEqual(app.state, .runningForeground)
        }
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    @MainActor func testDraftSkillsAndAIEditorThroughProductionNavigation() {
        let app = launch(storeID: "navigation-" + UUID().uuidString)
        XCTAssertTrue(app.tabBars.buttons["Files"].exists)
        XCTAssertTrue(app.tabBars.buttons["Conversations"].isSelected)
        XCTAssertTrue(app.tabBars.buttons["Settings"].exists)
        capture(app, "R3-home-light")
        app.buttons["chats.new"].tap()
        let input = app.textViews["composer.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap(); input.typeText("/ Draft to keep")
        XCTAssertFalse(app.otherElements["composer.skillMenu"].exists)
        app.buttons["composer.skills"].tap()
        XCTAssertTrue(app.buttons["composer.skill.documents"].waitForExistence(timeout: 5))
        XCTAssertEqual(input.value as? String, "/ Draft to keep")
        capture(app, "R4-skill-menu")
        app.buttons["composer.skill.documents"].tap()
        XCTAssertEqual(input.value as? String, "/ Draft to keep")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        back(app)
        let draft = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "chats.draft.")).firstMatch
        XCTAssertTrue(app.buttons["chats.drafts"].waitForExistence(timeout: 10))
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["chats.drafts"].waitForExistence(timeout: 20))
        app.buttons["chats.drafts"].tap()
        XCTAssertTrue(draft.waitForExistence(timeout: 10))
        draft.tap()
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        XCTAssertEqual(input.value as? String, "/ Draft to keep")
        app.buttons["composer.polish"].tap()
        XCTAssertTrue(app.otherElements["rewrite.editor"].waitForExistence(timeout: 10))
        app.buttons["rewrite.generate"].tap()
        let apply = app.buttons["rewrite.apply"]
        XCTAssertTrue(apply.waitForExistence(timeout: 15))
        let enabled = NSPredicate(format: "enabled == true")
        expectation(for: enabled, evaluatedWith: apply)
        waitForExpectations(timeout: 15)
        capture(app, "R5-editor-preview")
        apply.tap()
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        XCTAssertEqual(input.value as? String, "Polished: / Draft to keep")
        app.buttons["composer.undoPolish"].tap()
        XCTAssertEqual(input.value as? String, "/ Draft to keep")
        XCTAssertFalse(app.buttons["message.copy"].exists)
    }

    @MainActor func testPreviewArchiveAndUnreadUseRealListState() {
        let app = launch()
        app.buttons["chats.new"].tap()
        let input = app.textViews["composer.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap(); input.typeText("short")
        app.buttons["composer.send"].tap()
        XCTAssertTrue(app.staticTexts["message.completed"].waitForExistence(timeout: 25))
        capture(app, "R4-bubbles-light")
        back(app)
        let cell = app.cells.matching(NSPredicate(format: "identifier BEGINSWITH %@", "chat.history.row.")).firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 10))
        cell.press(forDuration: 0.8)
        XCTAssertTrue(app.buttons["Mark as unread"].waitForExistence(timeout: 10))
        capture(app, "R3-native-preview")
        app.buttons["Mark as unread"].tap()
        cell.press(forDuration: 0.8)
        XCTAssertTrue(app.buttons["Mark as read"].waitForExistence(timeout: 10))
        app.buttons["Archive"].tap()
        XCTAssertTrue(app.buttons["chats.archived"].waitForExistence(timeout: 10))
        app.buttons["chats.archived"].tap()
        XCTAssertTrue(cell.waitForExistence(timeout: 10))
        cell.press(forDuration: 0.8)
        XCTAssertTrue(app.buttons["Mark as read"].waitForExistence(timeout: 10))
        app.buttons["Open chat"].tap()
        XCTAssertTrue(app.staticTexts["message.completed"].waitForExistence(timeout: 10))
        back(app)
        cell.press(forDuration: 0.8)
        XCTAssertTrue(app.buttons["Mark as unread"].waitForExistence(timeout: 10))
    }

    @MainActor func testThousandConversationScrollingAndProjectSwitchingMetrics() {
        let app = XCUIApplication()
        app.launchArguments = ["-familiar.ui-testing", "1", "-familiar.chat-testing", "1", "-familiar.chat-list-count", "1000", "-AppleLanguages", "(en)"]
        app.launch()
        let list = app.collectionViews["chats.list"].firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 25))
        XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: 20))
        XCTAssertEqual(app.webViews.count, 0)
        let options = XCTMeasureOptions(); options.iterationCount = 3
        measure(metrics: [XCTOSSignpostMetric.scrollingAndDecelerationMetric, XCTMemoryMetric(application: app)], options: options) {
            list.swipeUp(velocity: .fast)
            list.swipeDown(velocity: .fast)
        }
        for title in ["Project 1", "Project 2", "Recent"] {
            let button = app.buttons[title].firstMatch
            if !button.isHittable { app.scrollViews.firstMatch.swipeLeft() }
            XCTAssertTrue(button.exists); button.tap()
            XCTAssertTrue(list.exists)
        }
        capture(app, "R6-thousand-conversations")
    }

    @MainActor func testHomeDarkAndLargeTypeScreenshots() {
        for (appearance, large) in [("dark", false), ("light", true)] {
            let app = launch(appearance: appearance, large: large)
            capture(app, "R3-home-" + appearance + (large ? "-large" : ""))
            app.buttons["chats.new"].tap()
            let input = app.textViews["composer.input"]
            XCTAssertTrue(input.waitForExistence(timeout: 10))
            input.tap(); input.typeText("Markdown")
            app.buttons["composer.send"].tap()
            XCTAssertTrue(app.staticTexts["message.completed"].waitForExistence(timeout: 25))
            capture(app, "R4-rich-bubbles-" + appearance + (large ? "-large" : ""))
            app.terminate()
        }
    }
}
