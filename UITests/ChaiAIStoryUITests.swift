import XCTest

final class ChaiAIStoryUITests: XCTestCase {
    func testFreshInstallSettingsAndCreationDraft() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"]
        app.launch()
        XCTAssertTrue(app.buttons["開始遊戲"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["API 設定／說明"].exists)
        app.buttons["API 設定／說明"].tap()
        XCTAssertTrue(app.staticTexts["尚未儲存金鑰"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["驗證連線與所選模型（可能計費）"].isEnabled)
        app.buttons["完成"].tap()
        app.buttons["開始遊戲"].tap()
        XCTAssertTrue(app.staticTexts["1 / 6 · 故事類型"].waitForExistence(timeout: 5))
        app.buttons["下一步"].tap()
        XCTAssertTrue(app.staticTexts["2 / 6 · 世界模板"].waitForExistence(timeout: 5))
        app.buttons["上一步"].tap()
        XCTAssertTrue(app.staticTexts["1 / 6 · 故事類型"].exists)
        app.buttons["儲存草稿並離開"].tap()
        XCTAssertTrue(app.buttons["開始遊戲"].waitForExistence(timeout: 5))
        // No generation request or fake story is allowed without a key.
        XCTAssertFalse(app.buttons["繼續遊戲"].exists)
    }
}
