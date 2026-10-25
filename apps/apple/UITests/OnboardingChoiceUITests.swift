import XCTest

@MainActor
final class OnboardingChoiceUITests: XCTestCase {
    func testSelectedCharacterResumesAndBecomesCurrentGallery() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["REPICK_ONBOARDING_CHOICE_TEST"] == "1")
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset", "-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launch()
        let hachiware = app.buttons["onboarding.character.hachiware"]
        XCTAssertTrue(hachiware.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["onboarding.character.chiikawa"].exists)
        XCTAssertTrue(app.buttons["onboarding.character.usagi"].exists)
        for character in ["hachiware", "chiikawa", "usagi"] {
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "3D 미리보기 준비됨"),
                                                  object: app.buttons["onboarding.character.\(character)"])
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed)
        }
        hachiware.tap()
        XCTAssertTrue(hachiware.isSelected)
        capture("Bright yellow character choice", app)
        app.buttons["onboarding.next"].tap()
        let name = app.textFields["onboarding.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        let initialName = name.value as? String ?? ""
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: initialName.count) + "모찌")
        XCTAssertEqual(name.value as? String, "모찌")
        capture("Name question with chosen character", app)
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.sliders["onboarding.height"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments[0] = "--ui-testing-use-store"
        app.launch()
        XCTAssertTrue(app.sliders["onboarding.height"].waitForExistence(timeout: 15))
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.sliders["onboarding.weight"].waitForExistence(timeout: 5))
        app.buttons["onboarding.next"].tap()
        app.buttons["onboarding.gender.notSpecified"].tap()
        app.buttons["onboarding.next"].tap()
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.tabBars.buttons["꾸미기"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.navigationBars["모찌"].exists)
        app.tabBars.buttons["꾸미기"].tap()
        for style in ["mermaidIsland", "pajamas", "gyaru"] {
            XCTAssertTrue(app.buttons["wardrobe.costume.hachiware.\(style)"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.buttons["wardrobe.costume.usagi.\(style)"].exists)
        }
        capture("Only selected Hachiware costume gallery", app)
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
