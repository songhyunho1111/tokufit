import XCTest

@MainActor
final class CostumeUITests: XCTestCase {
    private let styles = ["mermaidIsland", "pajamas", "gyaru"]

    func testFreshGalleryShowsOnlyCurrentCharacterAndRealLocks() throws {
        try require("gallery")
        let app = launch(reset: true)
        completeOnboarding(in: app)
        openWardrobe(in: app)
        assertGallery(character: "usagi", in: app)
        for style in styles {
            XCTAssertEqual(costume(character: "usagi", style: style, in: app).value as? String, "잠김")
        }

        let mermaid = costume(character: "usagi", style: "mermaidIsland", in: app)
        reveal(mermaid, in: app)
        mermaid.tap()
        let purchase = app.buttons["우사기 인어섬 · 500P"]
        XCTAssertTrue(purchase.waitForExistence(timeout: 5))
        XCTAssertFalse(purchase.isEnabled)
        app.buttons["취소"].tap()
        XCTAssertEqual(mermaid.value as? String, "잠김")

        let share = app.buttons["wardrobe.shareCurrent"]
        XCTAssertTrue(share.isHittable)
        XCTAssertGreaterThanOrEqual(share.frame.height, 44)
        XCTAssertLessThanOrEqual(share.frame.maxY, app.tabBars.firstMatch.frame.minY + 1)

        selectHachiware(in: app)
        openWardrobe(in: app)
        assertGallery(character: "hachiware", in: app)
        for style in styles {
            XCTAssertEqual(costume(character: "hachiware", style: style, in: app).value as? String, "잠김")
        }
        capture("Current character costume gallery and real locks", in: app)
    }

    func testCostumePurchaseCancelEquipAndPersistence() throws {
        try require("purchase")
        let app = launch()
        openWardrobe(in: app)
        assertGallery(character: "usagi", in: app)
        let mermaid = costume(character: "usagi", style: "mermaidIsland", in: app)
        XCTAssertEqual(mermaid.value as? String, "잠김")
        reveal(mermaid, in: app)
        mermaid.tap()
        let purchase = app.buttons["우사기 인어섬 · 500P"]
        XCTAssertTrue(purchase.waitForExistence(timeout: 5))
        XCTAssertTrue(purchase.isEnabled)
        app.buttons["취소"].tap()
        XCTAssertEqual(mermaid.value as? String, "잠김")

        mermaid.tap()
        XCTAssertTrue(purchase.waitForExistence(timeout: 5))
        purchase.tap()
        waitForValue("착용 중", of: mermaid)
        XCTAssertFalse(mermaid.isEnabled)
        XCTAssertEqual(app.staticTexts["wardrobe.currentStyle"].label, "인어섬")

        let unequip = app.buttons["wardrobe.unequip.costume"]
        reveal(unequip, in: app)
        unequip.tap()
        waitForValue("보유", of: mermaid)
        XCTAssertTrue(mermaid.isEnabled)
        mermaid.tap()
        waitForValue("착용 중", of: mermaid)

        app.terminate()
        app.launch()
        openWardrobe(in: app)
        waitForValue("착용 중", of: mermaid)
        XCTAssertEqual(app.staticTexts["wardrobe.currentStyle"].label, "인어섬")
        capture("Purchased costume remains equipped after relaunch", in: app)
    }

    func testFreeGachaReturnsCurrentCharacterCostumeOnce() throws {
        try require("free-gacha")
        let app = launch()
        openWardrobe(in: app)
        assertGallery(character: "usagi", in: app)
        let count = app.staticTexts["wardrobe.freeDraws"]
        reveal(count, in: app)
        let originalCount = try XCTUnwrap(Int(count.label.filter(\.isNumber)))
        XCTAssertGreaterThan(originalCount, 0)
        let draw = app.buttons["wardrobe.draw"]
        reveal(draw, in: app)
        draw.tap()
        let ball = app.buttons["gacha.ball"]
        XCTAssertTrue(ball.waitForExistence(timeout: 5))
        ball.doubleTap()
        let result = app.alerts["뽑기 결과"]
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        let receipt = result.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")
        XCTAssertTrue(receipt.contains("우사기"))
        XCTAssertTrue(["인어섬", "파자마", "갸루"].contains { receipt.contains($0) })
        XCTAssertTrue(receipt.contains("획득 · 착용 완료"))
        result.buttons["확인"].tap()
        reveal(count, in: app)
        XCTAssertEqual(Int(count.label.filter(\.isNumber)), originalCount - 1)
        for _ in 0..<8 where !app.buttons["wardrobe.category.costume"].isHittable { app.swipeDown() }
        XCTAssertEqual(styles.filter {
            costume(character: "usagi", style: $0, in: app).value as? String == "착용 중"
        }.count, 1)
        capture("Gacha grants and equips one current character costume", in: app)
    }

    private func require(_ mode: String) throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["REPICK_COSTUME_TEST_MODE"] == mode,
                          "Run only on an isolated costume QA simulator; purchase needs 500P and no Usagi costumes, free-gacha needs an earned free draw and no Usagi costumes.")
        continueAfterFailure = false
    }

    private func launch(reset: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [reset ? "--ui-testing-reset" : "--ui-testing-use-store",
                               "-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launch()
        return app
    }

    private func completeOnboarding(in app: XCUIApplication) {
        XCTAssertTrue(app.buttons["onboarding.character.usagi"].waitForExistence(timeout: 10))
        app.buttons["onboarding.character.usagi"].tap()
        app.buttons["onboarding.next"].tap()
        if app.textFields["onboarding.name"].waitForExistence(timeout: 3) { app.buttons["onboarding.next"].tap() }
        XCTAssertTrue(app.sliders["onboarding.height"].waitForExistence(timeout: 5))
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.sliders["onboarding.weight"].waitForExistence(timeout: 5))
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.buttons["onboarding.gender.notSpecified"].waitForExistence(timeout: 5))
        app.buttons["onboarding.gender.notSpecified"].tap()
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.steppers["onboarding.goal"].waitForExistence(timeout: 5))
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.tabBars.buttons["꾸미기"].waitForExistence(timeout: 15))
    }

    private func openWardrobe(in app: XCUIApplication) {
        let tab = app.tabBars.buttons["꾸미기"]
        XCTAssertTrue(tab.waitForExistence(timeout: 15))
        tab.tap()
        XCTAssertTrue(app.buttons["wardrobe.category.costume"].waitForExistence(timeout: 5))
    }

    private func assertGallery(character: String, in app: XCUIApplication) {
        for style in styles {
            XCTAssertTrue(costume(character: character, style: style, in: app).waitForExistence(timeout: 5))
        }
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "wardrobe.costume.")).count, 3)
        for other in ["usagi", "chiikawa", "hachiware"] where other != character {
            for style in styles {
                XCTAssertFalse(costume(character: other, style: style, in: app).exists)
            }
        }
    }

    private func costume(character: String, style: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons["wardrobe.costume.\(character).\(style)"]
    }

    private func selectHachiware(in app: XCUIApplication) {
        app.tabBars.buttons["설정"].tap()
        let edit = app.buttons["profile.edit"]
        reveal(edit, in: app)
        edit.tap()
        XCTAssertTrue(app.buttons["profile.character"].waitForExistence(timeout: 5))
        app.buttons["profile.character"].tap()
        app.buttons["하치와레"].tap()
        let save = app.buttons["save.profile"]
        XCTAssertTrue(save.isEnabled)
        save.tap()
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: save)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 10), .completed)
    }

    private func waitForValue(_ value: String, of element: XCUIElement) {
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 10), .completed)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }

    private func capture(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
