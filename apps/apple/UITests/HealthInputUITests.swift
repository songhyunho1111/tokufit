import XCTest

@MainActor
final class HealthInputUITests: XCTestCase {
    func testOptionalMealNutrientsPersistAfterRelaunch() throws {
        try requireInputFixture()
        let suffix = UUID().uuidString.prefix(8)
        let macroName = "Macro QA \(suffix)"
        let plainName = "Plain QA \(suffix)"
        print("Synthetic input meal names: \(macroName), \(plainName)")
        let app = launchApp()
        openMeal(in: app)
        replace(macroName, in: app.descendants(matching: .any)["meal.name"].firstMatch)
        replace("400", in: app.textFields["meal.calories"])
        closeMealKeyboard(in: app)
        let nutrients = app.descendants(matching: .any)["meal.nutrients"].firstMatch
        reveal(nutrients, in: app)
        nutrients.tap()
        XCTAssertTrue(app.textFields["meal.carbs"].waitForExistence(timeout: 5))
        replace("45", in: app.textFields["meal.carbs"])
        closeMealKeyboard(in: app)
        app.buttons["save.meal"].tap()
        let validation = app.staticTexts["meal.validation"]
        XCTAssertTrue(validation.waitForExistence(timeout: 5))
        XCTAssertTrue(validation.label.contains("세 항목"))
        XCTAssertTrue(app.buttons["save.meal"].exists)
        replace("20", in: app.textFields["meal.protein"])
        replace("15", in: app.textFields["meal.fat"])
        closeMealKeyboard(in: app)
        app.buttons["save.meal"].tap()
        waitForDismissal(of: app.buttons["save.meal"], in: app)

        openMeal(in: app)
        replace(plainName, in: app.descendants(matching: .any)["meal.name"].firstMatch)
        replace("100", in: app.textFields["meal.calories"])
        closeMealKeyboard(in: app)
        app.buttons["save.meal"].tap()
        waitForDismissal(of: app.buttons["save.meal"], in: app)

        app.terminate()
        app.launch()
        openMeal(in: app)
        let savedMeal = app.cells.containing(NSPredicate(format: "label CONTAINS %@", macroName)).firstMatch
        reveal(savedMeal, in: app)
        let savedNutrients = savedMeal.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "탄수화물 45g")).firstMatch
        reveal(savedNutrients, in: app)
        XCTAssertTrue(savedNutrients.label.contains("단백질 20g"))
        XCTAssertTrue(savedNutrients.label.contains("지방 15g"))
        let plainMeal = app.cells.containing(NSPredicate(format: "label CONTAINS %@", plainName)).firstMatch
        reveal(plainMeal, in: app)
        XCTAssertFalse(plainMeal.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "탄수화물")).firstMatch.exists)
        capture("Persisted optional meal nutrients", in: app)
        app.buttons["닫기"].tap()
    }

    func testWellnessUpsertPreservesMissingAndZeroSleep() throws {
        try requireInputFixture()
        let app = launchApp()
        openWellness(in: app)
        XCTAssertTrue(app.descendants(matching: .any)["wellness.date"].firstMatch.exists)
        setSleepEnabled(false, in: app)
        let condition = app.buttons["wellness.condition"]
        reveal(condition, in: app)
        condition.tap()
        let normal = app.buttons["3 · 보통"]
        if normal.waitForExistence(timeout: 3) { normal.tap() }
        else { app.staticTexts["3 · 보통"].tap() }
        XCTAssertTrue(app.buttons["wellness.save"].isEnabled)
        app.buttons["wellness.save"].tap()
        waitForDismissal(of: app.buttons["wellness.save"], in: app)

        app.terminate()
        app.launch()
        openWellness(in: app)
        XCTAssertEqual(app.switches["wellness.sleepEnabled"].value as? String, "0")
        XCTAssertFalse(app.steppers["wellness.sleepHours"].exists)
        let conditionLabel = app.buttons["wellness.condition"].label
            + String(describing: app.buttons["wellness.condition"].value ?? "")
        XCTAssertTrue(conditionLabel.contains("보통"))
        capture("Sleep omitted with recorded condition", in: app)

        setSleepEnabled(true, in: app)
        XCTAssertTrue(app.steppers["wellness.sleepHours"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.steppers["wellness.sleepHours"].value as? String, "0시간")
        XCTAssertEqual(app.steppers["wellness.sleepMinutes"].value as? String, "0분")
        app.buttons["wellness.save"].tap()
        waitForDismissal(of: app.buttons["wellness.save"], in: app)

        app.terminate()
        app.launch()
        openWellness(in: app)
        XCTAssertEqual(app.switches["wellness.sleepEnabled"].value as? String, "1")
        XCTAssertEqual(app.steppers["wellness.sleepHours"].value as? String, "0시간")
        XCTAssertEqual(app.steppers["wellness.sleepMinutes"].value as? String, "0분")
        XCTAssertTrue((app.buttons["wellness.condition"].label
                       + String(describing: app.buttons["wellness.condition"].value ?? "")).contains("보통"))
        capture("Explicit zero sleep persisted on same date", in: app)
        app.buttons["닫기"].tap()
    }

    private func requireInputFixture() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["REPICK_REPORT_TEST_MODE"] == "inputs",
                          "Requires an isolated simulator with the synthetic report fixture.")
        continueAfterFailure = false
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-use-store", "-apiBaseURL", "http://127.0.0.1:3100",
                               "-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["홈"].waitForExistence(timeout: 15))
        return app
    }

    private func openMeal(in app: XCUIApplication) {
        app.tabBars.buttons["홈"].tap()
        reveal(app.buttons["addMeal"], in: app)
        app.buttons["addMeal"].tap()
        XCTAssertTrue(app.buttons["save.meal"].waitForExistence(timeout: 5))
    }

    private func openWellness(in app: XCUIApplication) {
        XCTAssertTrue(app.tabBars.buttons["설정"].waitForExistence(timeout: 15))
        app.tabBars.buttons["설정"].tap()
        let reports = app.buttons["settings.healthReports"]
        reveal(reports, in: app)
        reports.tap()
        let wellness = app.buttons["reports.wellness"]
        reveal(wellness, in: app)
        wellness.tap()
        XCTAssertTrue(app.buttons["wellness.save"].waitForExistence(timeout: 5))
    }

    private func setSleepEnabled(_ enabled: Bool, in app: XCUIApplication) {
        let toggle = app.switches["wellness.sleepEnabled"]
        reveal(toggle, in: app)
        let expected = enabled ? "1" : "0"
        if toggle.value as? String != expected {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        XCTAssertEqual(toggle.value as? String, expected)
    }

    private func closeMealKeyboard(in app: XCUIApplication) {
        let done = app.buttons["meal.keyboardDone"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
    }

    private func replace(_ value: String, in field: XCUIElement) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        let displayed = field.value as? String ?? ""
        let current = displayed == field.placeholderValue ? "" : displayed
        if !current.isEmpty {
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)).tap()
        }
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + value)
        XCTAssertEqual(field.value as? String, value)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            app.swipeDown()
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }

    private func waitForDismissal(of element: XCUIElement, in app: XCUIApplication) {
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !element.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 10), .completed, app.debugDescription)
    }

    private func capture(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
