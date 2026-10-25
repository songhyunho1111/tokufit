import XCTest

@MainActor
final class HealthReportUITests: XCTestCase {
    // Live tests use an isolated simulator with synthetic records and an explicitly configured local server.
    func testWeeklyAndMonthlyReports() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["REPICK_REPORT_TEST_MODE"] == "live")
        continueAfterFailure = false
        let app = openReports()
        for period in ["주간", "월간"] {
            let picker = app.segmentedControls["reports.period"]
            for _ in 0..<12 where !picker.isHittable { app.swipeDown() }
            picker.buttons[period].tap()
            let generate = app.buttons["reports.generate"]
            XCTAssertTrue(generate.isEnabled)
            generate.tap()
            XCTAssertTrue(generate.waitForExistence(timeout: 90), "Generation did not finish")
            XCTAssertFalse(app.staticTexts["reports.status"].exists,
                           app.staticTexts["reports.status"].label)
            reveal(app.staticTexts["음식 기록"], app: app)
            let calendar = Calendar(identifier: .gregorian)
            let dayCount = period == "주간"
                ? min(5, (calendar.component(.weekday, from: Date()) + 5) % 7 + 1)
                : min(5, calendar.component(.day, from: Date()))
            XCTAssertTrue(app.staticTexts["\(dayCount)일 기록 · \(dayCount * 2)건"].exists)
            capture("\(period) report facts", app: app)
            reveal(app.staticTexts["수면·컨디션"], app: app)
            capture("\(period) nutrition and sleep", app: app)
            let usagi = app.descendants(matching: .any)["reports.usagi"].firstMatch
            reveal(usagi, app: app)
            XCTAssertFalse(usagi.label.isEmpty)
            capture("\(period) 3D Usagi reaction", app: app)
            let evaluation = app.staticTexts["reports.evaluation"]
            reveal(evaluation, app: app)
            XCTAssertFalse(evaluation.label.isEmpty)
            capture("\(period) Usagi evaluation", app: app)
            for index in 0..<3 {
                let recommendation = app.descendants(matching: .any)["reports.recommendation.\(index)"].firstMatch
                reveal(recommendation, app: app)
                XCTAssertFalse(recommendation.label.isEmpty)
            }
            capture("\(period) three changes", app: app)
        }
    }

    func testCachedReportWithoutServer() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["REPICK_REPORT_TEST_MODE"] == "offline")
        continueAfterFailure = false
        let app = openReports()
        reveal(app.staticTexts["보관된 리포트"], app: app)
        reveal(app.descendants(matching: .any)["reports.usagi"].firstMatch, app: app)
        reveal(app.staticTexts["reports.evaluation"], app: app)
        XCTAssertFalse(app.staticTexts["reports.status"].exists)
        capture("Offline cached weekly report", app: app)
        let generate = app.buttons["reports.generate"]
        for _ in 0..<12 where !generate.isHittable { app.swipeDown() }
        generate.tap()
        XCTAssertTrue(app.staticTexts["reports.status"].waitForExistence(timeout: 20))
        XCTAssertTrue(generate.waitForExistence(timeout: 5))
        capture("Offline generation error with retry", app: app)
        reveal(app.staticTexts["reports.evaluation"], app: app)
        XCTAssertFalse(app.staticTexts["reports.evaluation"].label.isEmpty)
    }

    private func openReports() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-use-store", "-apiBaseURL", "http://127.0.0.1:3100",
                               "-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["설정"].waitForExistence(timeout: 15))
        app.tabBars.buttons["설정"].tap()
        let link = app.buttons["settings.healthReports"]
        reveal(link, app: app)
        link.tap()
        XCTAssertTrue(app.buttons["reports.generate"].waitForExistence(timeout: 10))
        return app
    }

    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
