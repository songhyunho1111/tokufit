import XCTest

@MainActor
final class AttendanceUITests: XCTestCase {
    func testExplicitCheckInIsOncePerDayAndPersists() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["REPICK_ATTENDANCE_TEST_MODE"] == "isolated",
                          "Resets the UI-test save; run only on an isolated attendance QA simulator.")
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset", "-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launch()
        completeOnboarding(in: app)
        openAttendance(in: app)

        XCTAssertFalse(app.tabBars.buttons["홈"].isHittable)
        XCTAssertEqual(app.staticTexts["attendance.status"].label, "출석 전")
        XCTAssertEqual(app.staticTexts["attendance.weekSummary"].label, "이번 주 0일 출석")
        XCTAssertTrue(app.buttons["attendance.checkIn"].isEnabled)
        capture("Attendance before explicit check-in", in: app)

        app.buttons["attendance.help"].tap()
        XCTAssertTrue(app.alerts["출석 안내"].waitForExistence(timeout: 5))
        app.alerts.buttons["확인"].tap()
        app.buttons["attendance.checkIn"].tap()
        let checkedIn = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "출석 완료"),
            object: app.staticTexts["attendance.status"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [checkedIn], timeout: 10), .completed)
        XCTAssertFalse(app.buttons["attendance.checkIn"].isEnabled)
        XCTAssertEqual(app.staticTexts["attendance.weekSummary"].label, "이번 주 1일 출석")
        capture("Attendance saved once", in: app)

        let goal = app.buttons["attendance.goal"]
        reveal(goal, in: app)
        goal.tap()
        XCTAssertTrue(app.textFields["profile.name"].waitForExistence(timeout: 5))
        app.buttons["닫기"].tap()
        app.buttons["attendance.back"].tap()
        XCTAssertTrue(app.tabBars.buttons["홈"].isHittable)
        XCTAssertTrue(app.buttons["care.attendance"].label.contains("연속 1일 출석"))

        app.terminate()
        app.launchArguments[0] = "--ui-testing-use-store"
        app.launch()
        openAttendance(in: app)
        XCTAssertEqual(app.staticTexts["attendance.status"].label, "출석 완료")
        XCTAssertEqual(app.staticTexts["attendance.weekSummary"].label, "이번 주 1일 출석")
        XCTAssertFalse(app.buttons["attendance.checkIn"].isEnabled)
        capture("Attendance after relaunch", in: app)
    }

    private func openAttendance(in app: XCUIApplication) {
        let entry = app.buttons["care.attendance"]
        XCTAssertTrue(entry.waitForExistence(timeout: 15))
        reveal(entry, in: app)
        entry.tap()
        XCTAssertTrue(app.buttons["attendance.checkIn"].waitForExistence(timeout: 5))
    }

    private func completeOnboarding(in app: XCUIApplication) {
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
