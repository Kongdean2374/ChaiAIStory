import XCTest

final class ChaiAIStoryUITests: XCTestCase {
    func launchStory(health: String = "normal", large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-story-fixture", "--health=\(health)", "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        return app
    }
    func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<14 {
            if element.exists && element.isHittable { return }
            app.scrollViews["storyScroll"].swipeUp()
        }
    }
    func testHealthCardsDetailsAndCharacterAgreeWithoutAPI() {
        let app = launchStory(health: "injured")
        XCTAssertTrue(app.buttons["healthCard"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["locationCard"].label.contains("所在地"))
        XCTAssertTrue(app.buttons["healthCard"].label.contains("健康"))
        XCTAssertTrue(app.buttons["healthCard"].label.contains("頭暈不適"))
        app.buttons["healthCard"].tap()
        XCTAssertTrue(app.navigationBars["身體狀態"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["healthSymptoms"].label, "左腳踝腫痛，起身時頭暈。")
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'HP'")).firstMatch.exists)
        app.buttons["closeHealth"].tap()
        XCTAssertTrue(app.buttons["healthCard"].exists)
        app.tabBars.buttons["角色"].tap()
        XCTAssertTrue(app.staticTexts["healthSymptoms"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["healthSymptoms"].label, "左腳踝腫痛，起身時頭暈。")
    }
    func testVerticalChoicesKeyboardAndTabBar() {
        let app = launchStory()
        let window = app.windows.firstMatch.frame
        for index in 0..<5 {
            let choice = app.buttons["storyChoice\(index)"]
            scrollTo(choice, in: app)
            XCTAssertTrue(choice.isHittable)
            XCTAssertGreaterThanOrEqual(choice.frame.height, 44)
            XCTAssertGreaterThanOrEqual(choice.frame.minX, window.minX)
            XCTAssertLessThanOrEqual(choice.frame.maxX, window.maxX)
            XCTAssertGreaterThan(choice.label.count, 20)
        }
        let input = app.textFields["storyInput"].exists ? app.textFields["storyInput"] : app.textViews["storyInput"]
        XCTAssertTrue(input.isHittable)
        input.tap(); input.typeText("test")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let send = app.buttons["sendAction"]
        XCTAssertTrue(send.isHittable)
        XCTAssertLessThanOrEqual(send.frame.maxY, app.keyboards.firstMatch.frame.minY)
        app.buttons["收起鍵盤"].tap()
        app.tabBars.buttons["背包"].tap()
        app.tabBars.buttons["劇情"].tap()
        XCTAssertTrue(app.buttons["healthCard"].exists)
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.buttons["healthCard"].waitForExistence(timeout: 5))
    }
    func testAccessibilityTextKeepsCardsAndChoicesOperable() {
        let app = launchStory(health: "cold", large: true)
        XCTAssertTrue(app.buttons["healthCard"].waitForExistence(timeout: 10))
        app.buttons["healthCard"].tap()
        XCTAssertEqual(app.staticTexts["healthFeeling"].label, "冷得發抖")
        app.buttons["closeHealth"].tap()
        let choice = app.buttons["storyChoice4"]
        scrollTo(choice, in: app)
        XCTAssertTrue(choice.isHittable)
        XCTAssertLessThanOrEqual(choice.frame.maxX, app.windows.firstMatch.frame.maxX)
        XCTAssertGreaterThan(choice.frame.height, 44)
        XCTAssertTrue(app.buttons["sendAction"].exists)
    }
    func testVersionAndSavedRangeVisible() {
        let app = launchStory(health: "waking")
        app.tabBars.buttons["設定"].tap()
        XCTAssertTrue(app.staticTexts["appVersion"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["appVersion"].label, "版本 1.1.0（Build 2）")
        XCTAssertEqual(app.staticTexts["savedNarrativeRange"].label, "目前有效：150～250 字")
    }
    func testFreshInstallSettingsAndCreationDraft() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"]
        app.launch()
        XCTAssertTrue(app.buttons["開始遊戲"].waitForExistence(timeout: 10))
        app.buttons["開始遊戲"].tap()
        XCTAssertTrue(app.staticTexts["1 / 6 · 故事類型"].waitForExistence(timeout: 5))
        app.buttons["下一步"].tap()
        XCTAssertTrue(app.staticTexts["2 / 6 · 世界模板"].waitForExistence(timeout: 5))
        app.buttons["上一步"].tap()
        app.buttons["儲存草稿並離開"].tap()
        XCTAssertTrue(app.buttons["開始遊戲"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["繼續遊戲"].exists)
    }
}
