import XCTest

@MainActor
final class FoodCaloriesUITests: XCTestCase {
    // Run only on the isolated QA simulator with the public banana photo first in its photo library.
    func testPhotoReviewRegistersEditedMealOnceAndPersists() throws {
        try requireLiveFixture()
        let name = "Food photo QA \(UUID().uuidString.prefix(8))"
        let app = launchApp()
        openFoodTab(in: app)
        selectFirstPhoto(in: app)

        let analyze = app.buttons["food.analyze"]
        XCTAssertTrue(analyze.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["food.confirm"].exists)
        XCTAssertFalse(app.buttons["food.register"].exists)
        analyze.tap()
        let confirm = app.buttons["food.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 90), app.debugDescription)
        XCTAssertFalse(app.staticTexts["food.status"].exists)
        XCTAssertFalse(app.textFields["food.calories"].exists)
        XCTAssertFalse(app.buttons["food.register"].exists)
        capture("Recognized food awaits confirmation", in: app)
        confirm.tap()

        replace(name, in: app.descendants(matching: .any)["food.name"].firstMatch, app: app)
        replace("1인분", in: app.descendants(matching: .any)["food.portion"].firstMatch, app: app)
        replace("410", in: app.textFields["food.calories"], app: app)
        replace("45", in: app.textFields["food.carbs"], app: app)
        replace("20", in: app.textFields["food.protein"], app: app)
        replace("15", in: app.textFields["food.fat"], app: app)
        app.buttons["food.back"].tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["food.register"].exists)
        confirm.tap()
        XCTAssertEqual(app.descendants(matching: .any)["food.name"].firstMatch.value as? String, name)
        XCTAssertEqual(app.textFields["food.calories"].value as? String, "410")

        openMeals(in: app)
        XCTAssertFalse(mealRows(named: name, in: app).firstMatch.exists,
                       "Confirmation and editing must not save a meal.")
        app.buttons["닫기"].tap()
        openFoodTab(in: app)
        XCTAssertEqual(app.descendants(matching: .any)["food.name"].firstMatch.value as? String, name)
        let register = app.buttons["food.register"]
        reveal(register, in: app)
        capture("Editable nutrition before explicit registration", in: app)
        register.tap(withNumberOfTaps: 2, numberOfTouches: 1)
        let saved = app.staticTexts["food.saved"]
        XCTAssertTrue(saved.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(saved.label, "푸루(기록했어!)")
        XCTAssertFalse(app.buttons["food.register"].exists)
        capture("Saved meal with silent Usagi confirmation", in: app)

        app.terminate()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["홈"].waitForExistence(timeout: 15))
        openMeals(in: app)
        let rows = mealRows(named: name, in: app)
        reveal(rows.firstMatch, in: app)
        XCTAssertEqual(rows.count, 1, "Repeated registration must create one record.")
        let row = rows.firstMatch
        XCTAssertTrue(row.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "410 kcal")).firstMatch.exists)
        let nutrients = row.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "탄수화물 45g")).firstMatch
        XCTAssertTrue(nutrients.exists)
        XCTAssertTrue(nutrients.label.contains("단백질 20g"))
        XCTAssertTrue(nutrients.label.contains("지방 15g"))
        XCTAssertFalse(row.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "AI 추정")).firstMatch.exists,
                       "Edited values must be saved with the manual source.")
        capture("One edited meal persisted after relaunch", in: app)
        app.buttons["닫기"].tap()
    }

    func testCameraDenialOrUnavailableKeepsPhotoLibraryAvailable() throws {
        try requireLiveFixture()
        #if !targetEnvironment(simulator)
        throw XCTSkip("This case checks camera denial or unavailability on an isolated simulator, not physical capture.")
        #else
        let app = launchApp()
        openFoodTab(in: app)
        app.buttons["food.camera"].tap()
        dismissCameraPermissionIfPresent()
        let status = app.staticTexts["food.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertTrue(status.label.contains("카메라"))
        XCTAssertTrue(app.buttons["food.library"].isEnabled)
        XCTAssertFalse(app.staticTexts["food.saved"].exists)
        selectFirstPhoto(in: app)
        XCTAssertTrue(app.buttons["food.analyze"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["food.confirm"].exists)
        capture("Photo library after camera denial or unavailability", in: app)
        #endif
    }

    private func requireLiveFixture() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["REPICK_FOOD_TEST_MODE"] == "live",
                          "Requires the isolated QA profile, public banana fixture and live local API.")
        continueAfterFailure = false
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-use-store", "-apiBaseURL", "http://127.0.0.1:3100",
                               "-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launch()
        dismissCameraPermissionIfPresent()
        XCTAssertTrue(app.tabBars.buttons["음식 칼로리"].waitForExistence(timeout: 15))
        return app
    }

    private func openFoodTab(in app: XCUIApplication) {
        app.tabBars.buttons["음식 칼로리"].tap()
    }

    private func selectFirstPhoto(in app: XCUIApplication) {
        let library = app.buttons["food.library"]
        reveal(library, in: app)
        library.tap()
        let photo = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 15), "Import the public banana fixture into the isolated QA photo library first.")
        photo.tap()
    }

    private func dismissCameraPermissionIfPresent() {
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        guard alert.waitForExistence(timeout: 2) else { return }
        let deny = alert.buttons.matching(NSPredicate(format: "label IN %@", ["허용 안 함", "Don't Allow", "Don’t Allow"])).firstMatch
        if deny.exists { deny.tap() }
    }

    private func openMeals(in app: XCUIApplication) {
        app.tabBars.buttons["홈"].tap()
        let addMeal = app.buttons["addMeal"]
        reveal(addMeal, in: app)
        addMeal.tap()
        XCTAssertTrue(app.buttons["save.meal"].waitForExistence(timeout: 5))
    }

    private func mealRows(named name: String, in app: XCUIApplication) -> XCUIElementQuery {
        app.cells.containing(NSPredicate(format: "label CONTAINS %@", name))
    }

    private func replace(_ value: String, in field: XCUIElement, app: XCUIApplication) {
        reveal(field, in: app)
        field.tap()
        let displayed = field.value as? String ?? ""
        let current = displayed == field.placeholderValue ? "" : displayed
        if !current.isEmpty {
            field.press(forDuration: 1.2)
            let labels = ["Select All", "전체 선택", "모두 선택"]
            let selectAll = app.buttons.matching(NSPredicate(format: "label IN %@", labels)).firstMatch
            let menuItem = app.menuItems.matching(NSPredicate(format: "label IN %@", labels)).firstMatch
            if selectAll.waitForExistence(timeout: 2) { selectAll.tap() }
            else if menuItem.exists { menuItem.tap() }
            else { field.doubleTap() }
        }
        field.typeText(value)
        XCTAssertEqual(field.value as? String, value)
        let done = app.buttons["food.keyboardDone"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
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

    private func capture(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
