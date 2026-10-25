import XCTest

@MainActor
final class GrowthFlowUITests: XCTestCase {
    func testMilestoneCheckInAwardsOneChance() throws {
        try require("milestone")
        let app = launch()
        openAttendance(app)
        XCTAssertEqual(app.staticTexts["attendance.status"].label, "출석 전")
        capture("Reference attendance before milestone", app)
        app.buttons["attendance.checkIn"].doubleTap()
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "출석 완료"),
                                               object: app.staticTexts["attendance.status"])
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 10), .completed)
        XCTAssertFalse(app.buttons["attendance.checkIn"].isEnabled)
        app.buttons["attendance.back"].tap()
        XCTAssertTrue(app.buttons["care.attendance"].label.contains("연속 10일 출석"))
        app.tabBars.buttons["꾸미기"].tap()
        let free = app.staticTexts["wardrobe.freeDraws"]
        reveal(free, app)
        XCTAssertEqual(Int(free.label.filter(\.isNumber)), 1)
        capture("One earned milestone chance", app)
    }

    func testMissedCheckInRestoresAppearance() throws {
        try require("missed")
        let app = launch()
        capture("Missed attendance fiery character", app)
        openAttendance(app)
        capture("Fiery attendance illustration", app)
        XCTAssertEqual(app.staticTexts["attendance.status"].label, "출석 전")
        app.buttons["attendance.checkIn"].tap()
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "출석 완료"),
                                               object: app.staticTexts["attendance.status"])
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 10), .completed)
        capture("Check-in restores normal illustration", app)
        app.buttons["attendance.back"].tap()
        XCTAssertTrue(app.buttons["care.attendance"].label.contains("연속 1일 출석"))
    }

    func testStrengthDurationCreatesEstimatedEnergy() throws {
        try require("exercise")
        let app = launch()
        app.tabBars.buttons["운동"].tap()
        app.segmentedControls["exercise.mode"].buttons["실내"].tap()
        let activity = app.buttons["exercise.indoor.activity"]
        XCTAssertTrue(activity.waitForExistence(timeout: 5))
        activity.tap()
        app.buttons["근력 운동"].tap()
        app.buttons["exercise.indoor.start"].tap()
        XCTAssertTrue(app.buttons["exercise.complete"].waitForExistence(timeout: 10))
        app.buttons["exercise.complete"].tap()
        let minutes = app.textFields["exercise.minutes"]
        XCTAssertTrue(minutes.waitForExistence(timeout: 5))
        minutes.tap()
        minutes.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)).tap()
        let original = minutes.value as? String ?? ""
        minutes.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: original.count) + "30")
        XCTAssertEqual(minutes.value as? String, "30")
        app.buttons["exercise.keyboardDone"].tap()
        let estimate = app.staticTexts["exercise.estimatedCalories"]
        reveal(estimate, app)
        XCTAssertTrue(estimate.label.contains("70"))
        capture("Strength exercise automatic estimate", app)
        app.buttons["exercise.save"].tap()
        XCTAssertTrue(app.buttons["exercise.indoor.start"].waitForExistence(timeout: 10))
        app.tabBars.buttons["홈"].tap()
        capture("Home reflects saved exercise growth", app)
    }

    private func require(_ mode: String) throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["REPICK_GROWTH_TEST_MODE"] == mode)
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-use-store", "-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["홈"].waitForExistence(timeout: 15))
        return app
    }

    private func openAttendance(_ app: XCUIApplication) {
        let entry = app.buttons["care.attendance"]
        reveal(entry, app)
        entry.tap()
        XCTAssertTrue(app.buttons["attendance.checkIn"].waitForExistence(timeout: 5))
    }

    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<10 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
