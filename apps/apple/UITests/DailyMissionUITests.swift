import XCTest

@MainActor
final class DailyMissionUITests: XCTestCase {
    func testManualStairsRequireCheckInAndRewardPersistsOnce() throws {
        let app = try launchFreshApp()
        openMissions(in: app)
        app.buttons["mission.stairs"].tap()

        let action = app.buttons["mission.action"]
        reveal(action, in: app)
        action.tap()
        let stairCount = app.textFields["mission.stairCount"]
        XCTAssertTrue(stairCount.waitForExistence(timeout: 5))
        replaceText(in: stairCount, with: "5")
        XCTAssertEqual(stairCount.value as? String, "5")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let saveStairs = app.buttons["mission.saveStairs"]
        reveal(saveStairs, in: app)
        saveStairs.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        expectLabel("5 / 5", on: app.staticTexts["mission.progress"])
        XCTAssertFalse(app.staticTexts["mission.claimed"].exists)

        reveal(action, in: app)
        action.tap()
        let checkIn = app.buttons["attendance.checkIn"]
        XCTAssertTrue(checkIn.waitForExistence(timeout: 5))
        let attendanceImage = XCTAttachment(screenshot: app.screenshot())
        attendanceImage.name = "Updated attendance screen"
        attendanceImage.lifetime = .keepAlways
        add(attendanceImage)
        checkIn.tap()
        expectLabel("출석 완료", on: app.staticTexts["attendance.status"])
        app.buttons["attendance.back"].tap()

        reveal(action, in: app)
        action.tap()
        XCTAssertTrue(app.staticTexts["mission.claimed"].waitForExistence(timeout: 5))
        XCTAssertFalse(action.exists && action.isEnabled)
        app.buttons["mission.close"].tap()
        XCTAssertTrue(app.staticTexts["보유 포인트 5"].waitForExistence(timeout: 5))

        app.terminate()
        app.launchArguments[0] = "--ui-testing-use-store"
        app.launch()
        openMissions(in: app)
        app.buttons["mission.stairs"].tap()
        expectLabel("5 / 5", on: app.staticTexts["mission.progress"])
        XCTAssertTrue(app.staticTexts["mission.claimed"].exists)
        XCTAssertFalse(app.buttons["mission.action"].exists && app.buttons["mission.action"].isEnabled)
        app.buttons["mission.close"].tap()
        XCTAssertTrue(app.staticTexts["보유 포인트 5"].waitForExistence(timeout: 5))
    }

    func testFirstCalorieRangeKeepsUnrecordedNutritionNeutral() throws {
        let app = try launchFreshApp()
        let status = app.staticTexts["care.nutrition.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertEqual(status.label, "나의 범위를 설정해 주세요")
        configureCalorieRange(in: app)
        expectLabel("아직 식사 기록이 없어요", on: status)
        XCTAssertFalse(app.buttons["care.nutrition.configure"].exists)
    }

    func testThreeMealsAndExplicitFoodDayConfirmationEarnSeparateRewards() throws {
        let app = try launchFreshApp()
        configureCalorieRange(in: app)
        openMissions(in: app)
        app.buttons["mission.threeMeals"].tap()

        for (index, kind) in ["아침", "점심", "저녁"].enumerated() {
            let action = app.buttons["mission.action"]
            reveal(action, in: app)
            action.tap()
            let mealKind = app.segmentedControls["meal.kind"]
            XCTAssertTrue(mealKind.waitForExistence(timeout: 5))
            mealKind.buttons[kind].tap()
            replaceText(in: app.descendants(matching: .any)["meal.name"].firstMatch, with: "미션 테스트 \(kind)")
            replaceText(in: app.textFields["meal.calories"], with: "400")
            if app.buttons["meal.keyboardDone"].isHittable { app.buttons["meal.keyboardDone"].tap() }
            app.buttons["save.meal"].tap()
            expectLabel("\(index + 1) / 3", on: app.staticTexts["mission.progress"])
        }

        let action = app.buttons["mission.action"]
        reveal(action, in: app)
        action.tap()
        let checkIn = app.buttons["attendance.checkIn"]
        XCTAssertTrue(checkIn.waitForExistence(timeout: 5))
        checkIn.tap()
        expectLabel("출석 완료", on: app.staticTexts["attendance.status"])
        app.buttons["attendance.back"].tap()
        reveal(action, in: app)
        action.tap()
        XCTAssertTrue(app.staticTexts["mission.claimed"].waitForExistence(timeout: 5))

        let calorieMission = app.buttons["mission.calorieRange"]
        for _ in 0..<8 where !calorieMission.isHittable { app.swipeDown() }
        XCTAssertTrue(calorieMission.isHittable)
        calorieMission.tap()
        expectLabel("0 / 1", on: app.staticTexts["mission.progress"])
        expectLabel("5P", on: app.staticTexts["mission.rewardPoints"])
        reveal(action, in: app)
        action.tap()
        let confirm = app.buttons["mission.confirmFoodDay"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        expectLabel("1 / 1", on: app.staticTexts["mission.progress"])
        reveal(action, in: app)
        action.tap()
        XCTAssertTrue(app.staticTexts["mission.claimed"].waitForExistence(timeout: 5))
        app.buttons["mission.close"].tap()
        XCTAssertTrue(app.staticTexts["보유 포인트 10"].waitForExistence(timeout: 5))
        expectLabel("기록한 섭취량이 범위 안에 있어요", on: app.staticTexts["care.nutrition.status"])
    }

    private func configureCalorieRange(in app: XCUIApplication) {
        let configure = app.buttons["care.nutrition.configure"]
        reveal(configure, in: app)
        configure.tap()
        let enabled = app.switches["profile.calorieEnabled"]
        reveal(enabled, in: app)
        enabled.tap()
        let minimum = app.textFields["profile.calorieMinimum"]
        XCTAssertTrue(minimum.waitForExistence(timeout: 5))
        replaceText(in: minimum, with: "1000")
        replaceText(in: app.textFields["profile.calorieMaximum"], with: "2000")
        app.buttons["save.profile"].tap()
        expectLabel("아직 식사 기록이 없어요", on: app.staticTexts["care.nutrition.status"])
    }

    private func launchFreshApp() throws -> XCUIApplication {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["REPICK_MISSION_TEST_MODE"] == "isolated",
                          "Resets the UI-test save; run only on an isolated mission QA simulator.")
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset", "-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.next"].waitForExistence(timeout: 10))
        if app.buttons["onboarding.character.usagi"].exists {
            app.buttons["onboarding.character.usagi"].tap()
            app.buttons["onboarding.next"].tap()
        }
        if app.textFields["onboarding.name"].exists { app.buttons["onboarding.next"].tap() }
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.sliders["onboarding.weight"].waitForExistence(timeout: 3))
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.buttons["onboarding.gender.notSpecified"].waitForExistence(timeout: 3))
        app.buttons["onboarding.gender.notSpecified"].tap()
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.steppers["onboarding.goal"].waitForExistence(timeout: 3))
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15))
        return app
    }

    private func openMissions(in app: XCUIApplication) {
        let entry = app.buttons["care.missions"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        reveal(entry, in: app)
        entry.tap()
        XCTAssertTrue(app.buttons["mission.stairs"].waitForExistence(timeout: 5))
    }

    private func replaceText(in field: XCUIElement, with text: String) {
        field.tap()
        let previous = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count) + text)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }

    private func expectLabel(_ label: String, on element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", label), object: element
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }
}
