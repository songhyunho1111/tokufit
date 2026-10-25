import XCTest

@MainActor
final class GachaUITests: XCTestCase {
    func testFreeDrawBackAndDoubleTapPersistExactlyOneUse() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["REPICK_GACHA_TEST_MODE"] == "free",
                          "Requires an isolated QA profile with at least one earned free draw.")
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-use-store", "-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launch()
        openWardrobe(in: app)

        let count = app.staticTexts["wardrobe.freeDraws"]
        reveal(count, in: app)
        let originalCount = try freeDrawCount(count.label)
        XCTAssertGreaterThan(originalCount, 0)
        XCTAssertTrue(app.staticTexts["wardrobe.drawPayment"].label.contains("무료 기회 1회"))
        let entry = app.buttons["wardrobe.draw"]
        reveal(entry, in: app)
        XCTAssertTrue(entry.isEnabled)
        entry.tap()
        assertReferenceScreen(in: app)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Static reference gacha screen"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.buttons["gacha.back"].tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        XCTAssertEqual(try freeDrawCount(count.label), originalCount)
        entry.tap()
        XCTAssertTrue(app.buttons["gacha.ball"].waitForExistence(timeout: 5))
        app.buttons["gacha.ball"].doubleTap()
        let result = app.alerts["뽑기 결과"]
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        result.buttons["확인"].tap()
        XCTAssertFalse(app.buttons["gacha.ball"].exists)
        XCTAssertEqual(try freeDrawCount(count.label), originalCount - 1)

        app.terminate()
        app.launch()
        openWardrobe(in: app)
        reveal(count, in: app)
        XCTAssertEqual(try freeDrawCount(count.label), originalCount - 1)
    }

    private func assertReferenceScreen(in app: XCUIApplication) {
        XCTAssertTrue(app.buttons["gacha.ball"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["gacha.subtitle"].label, "미션 보상")
        XCTAssertEqual(app.staticTexts["gacha.title"].label, "토쿠볼 오픈")
        XCTAssertEqual(app.staticTexts["gacha.prompt"].label, "탭하여 열어보세요")
        XCTAssertGreaterThanOrEqual(app.buttons["gacha.back"].frame.width, 44)
        XCTAssertGreaterThanOrEqual(app.buttons["gacha.back"].frame.height, 44)
        XCTAssertFalse(app.tabBars.buttons["꾸미기"].isHittable)
    }

    private func openWardrobe(in app: XCUIApplication) {
        let tab = app.tabBars.buttons["꾸미기"]
        XCTAssertTrue(tab.waitForExistence(timeout: 15))
        tab.tap()
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }

    private func freeDrawCount(_ label: String) throws -> Int {
        try XCTUnwrap(Int(label.filter(\.isNumber)))
    }
}
