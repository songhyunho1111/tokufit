import XCTest
import CoreLocation

@MainActor
final class REPickUITests: XCTestCase {
    func testDeniedLocationOffersRecovery() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-use-store", "-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        let monitor = addUIInterruptionMonitor(withDescription: "Location and motion permissions") { alert in
            for label in ["허용 안 함", "Don't Allow", "Don’t Allow"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
        defer { removeUIInterruptionMonitor(monitor) }
        app.resetAuthorizationStatus(for: .location)
        app.launch()
        completeOnboardingIfNeeded(in: app)
        XCTAssertTrue(app.tabBars.buttons["운동"].waitForExistence(timeout: 15))
        app.tabBars.buttons["운동"].tap()
        app.buttons["walk.start"].tap()
        let permission = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if permission.waitForExistence(timeout: 5) {
            let deny = permission.buttons.matching(NSPredicate(format: "label IN %@", ["허용 안 함", "Don't Allow", "Don’t Allow"])).firstMatch
            XCTAssertTrue(deny.exists)
            deny.tap()
        } else if !app.buttons["위치 권한 설정 열기"].exists {
            throw XCTSkip("The simulator did not present a location permission prompt after authorization reset; verify denial on a device that supports the reset.")
        }
        XCTAssertTrue(app.buttons["위치 권한 설정 열기"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["walk.start"].exists)
        XCTAssertFalse(app.buttons["현재 위치로 이동"].isEnabled)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Location unavailable with recovery guidance"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testWorkoutFocusAndExit() throws {
        continueAfterFailure = false
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.4840451, longitude: 126.9293904),
            altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
            course: 270, speed: 1.4, timestamp: Date()
        ))
        defer { XCUIDevice.shared.location = nil }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-use-store", "-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launch()
        completeOnboardingIfNeeded(in: app)
        XCTAssertTrue(app.tabBars.buttons["운동"].waitForExistence(timeout: 15))
        let walkTab = app.tabBars.buttons["운동"]
        walkTab.tap()
        let start = app.buttons["walk.start"]
        if !start.waitForExistence(timeout: 3), !walkTab.isSelected { walkTab.tap() }
        XCTAssertTrue(start.waitForExistence(timeout: 8))
        let map = app.maps.firstMatch
        XCTAssertTrue(map.exists)
        XCTAssertLessThan(start.frame.maxY, app.tabBars.firstMatch.frame.minY)
        let ready = XCTAttachment(screenshot: app.screenshot())
        ready.name = "Glass start panel above tab bar"
        ready.lifetime = .keepAlways
        add(ready)
        start.tap()
        XCTAssertTrue(app.buttons["workout.menu"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.tabBars.buttons["홈"].isHittable)
        XCTAssertFalse(app.buttons["walk.start"].isHittable)
        let avatar = app.descendants(matching: .any)["walk.avatar"].firstMatch
        XCTAssertTrue(avatar.waitForExistence(timeout: 10))
        let cameraSettledAfter = Date().addingTimeInterval(1)
        let lowerFraming = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            Date() >= cameraSettledAfter && avatar.frame.midY > app.frame.height * 0.60
                && avatar.frame.midY < app.frame.height * 0.78 && avatar.frame.maxY < app.frame.height * 0.88
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [lowerFraming], timeout: 8), .completed,
                       "Avatar must sit below center with room for the workout menu: \(avatar.frame)")
        let focused = XCTAttachment(screenshot: app.screenshot())
        focused.name = "Focused workout map"
        focused.lifetime = .keepAlways
        add(focused)
        let initialWidth = avatar.frame.width
        map.pinch(withScale: 2, velocity: 1)
        followLocation(in: app)
        let enlarged = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            avatar.exists && avatar.frame.width > initialWidth * 1.25
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [enlarged], timeout: 8), .completed,
                       "Zoom in must enlarge the avatar: \(initialWidth) → \(avatar.frame.width)")
        let zoomedWidth = avatar.frame.width
        // Keep both closing touches clear of the floating menu at the map's bottom-right corner.
        avatar.pinch(withScale: 0.5, velocity: -1)
        followLocation(in: app)
        let reduced = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            avatar.exists && avatar.frame.width < zoomedWidth * 0.85
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [reduced], timeout: 8), .completed,
                       "Zoom out must shrink the avatar: \(zoomedWidth) → \(avatar.frame.width), initial \(initialWidth)")
        print("Avatar zoom widths: \(initialWidth) → \(zoomedWidth) → \(avatar.frame.width)")
        app.buttons["workout.menu"].tap()
        reveal(app.buttons["workout.end"], in: app)
        XCTAssertTrue(app.buttons["workout.end"].waitForExistence(timeout: 5))
        app.buttons["workout.end"].tap()
        XCTAssertTrue(app.textFields["exercise.minutes"].waitForExistence(timeout: 5))
        app.buttons["exercise.save"].tap()
        XCTAssertTrue(app.tabBars.buttons["홈"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["walk.start"].isHittable)
    }

    func testProfileAndWaterPersistAfterRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset", "-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launch()

        completeOnboardingIfNeeded(in: app)

        reveal(app.buttons["care.compare"], in: app)
        app.buttons["care.compare"].tap()
        XCTAssertEqual(app.buttons["care.compare"].value as? String, "펼침")
        let currentCharacter = app.descendants(matching: .any)["care.compareCurrent3d"].firstMatch
        let targetCharacter = app.descendants(matching: .any)["care.target3d"].firstMatch
        XCTAssertTrue(currentCharacter.waitForExistence(timeout: 10))
        XCTAssertTrue(targetCharacter.exists)
        XCTAssertEqual(currentCharacter.frame.height, targetCharacter.frame.height, accuracy: 1)
        XCTAssertEqual(currentCharacter.frame.width, targetCharacter.frame.width, accuracy: 1)
        let water = app.buttons["addWater"]
        XCTAssertTrue(water.waitForExistence(timeout: 10))
        for _ in 0..<5 where !water.isHittable { app.swipeDown() }
        water.tap()
        let amount = app.staticTexts["water.total"]
        XCTAssertTrue(amount.waitForExistence(timeout: 10))
        XCTAssertEqual(amount.label, "250 mL")

        app.buttons["addMeal"].tap()
        let food = app.descendants(matching: .any)["meal.name"].firstMatch
        enter("엽떡 1인분", into: food)
        enter("0", into: app.textFields["meal.calories"])
        app.buttons["save.meal"].tap()
        XCTAssertTrue(app.staticTexts["음식 이름과 1~5,000kcal 사이의 열량을 입력해 주세요."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["save.meal"].exists)
        app.buttons["닫기"].tap()
        app.buttons["addMeal"].tap()
        enter("엽떡 1인분", into: app.descendants(matching: .any)["meal.name"].firstMatch)
        enter("1200", into: app.textFields["meal.calories"])
        XCTAssertEqual(app.textFields["meal.calories"].value as? String, "1200")
        if !app.buttons["save.meal"].isHittable { app.swipeUp() }
        app.buttons["save.meal"].tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["save.meal"])
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 10), .completed, app.debugDescription)
        let mealTotal = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "1,?200 kcal")).firstMatch
        XCTAssertTrue(mealTotal.waitForExistence(timeout: 5))

        app.terminate()
        app.launchArguments = ["--ui-testing-use-store", "-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launch()
        XCTAssertTrue(water.waitForExistence(timeout: 15))
        if !amount.isHittable { app.swipeUp() }
        XCTAssertEqual(amount.label, "250 mL")
        XCTAssertTrue(mealTotal.exists)
        XCTAssertFalse(app.buttons["createUsagi"].exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Persisted water and Usagi"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let motionMenu = app.buttons["care.motionMenu"]
        for _ in 0..<3 where !motionMenu.isHittable { app.swipeDown() }
        motionMenu.tap()
        XCTAssertTrue(app.buttons["care.motion.grazing"].waitForExistence(timeout: 5))
        app.buttons["care.motion.grazing"].tap()
        XCTAssertEqual(app.buttons["care.character"].value as? String, "풀 먹기")

        app.tabBars.buttons["꾸미기"].tap()
        XCTAssertTrue(app.buttons["wardrobe.outfit.student"].waitForExistence(timeout: 5))
        reveal(app.buttons["wardrobe.draw"], in: app)
        XCTAssertTrue(app.buttons["wardrobe.draw"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["wardrobe.draw"].isEnabled)
        XCTAssertTrue(app.staticTexts["wardrobe.drawReason"].label.contains("목표"))

        app.tabBars.buttons["설정"].tap()
        XCTAssertTrue(app.navigationBars["설정"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["API 서버 주소"].exists)
        app.buttons["profile.edit"].tap()
        XCTAssertTrue(app.textFields["profile.height"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["profile.height"].value as? String, "170")
        XCTAssertEqual(app.textFields["profile.weight"].value as? String, "70")
        XCTAssertEqual(app.textFields["profile.target"].value as? String, "70")
        app.buttons["닫기"].tap()
        app.tabBars.buttons["홈"].tap()
        app.swipeDown()
        app.swipeDown()
        let character = XCTAttachment(screenshot: app.screenshot())
        character.name = "Current and target Usagi"
        character.lifetime = .keepAlways
        add(character)
    }

    func testDesignAuditScreens() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-use-store", "-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launch()
        completeOnboardingIfNeeded(in: app)
        XCTAssertTrue(app.buttons["care.motionMenu"].waitForExistence(timeout: 10))
        capture("Design Care", app: app)
        for _ in 0..<5 where !app.buttons["addMeal"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.buttons["addMeal"].isHittable)
        capture("Design Food action", app: app)
        for _ in 0..<5 where !app.buttons["addWater"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.buttons["addWater"].isHittable)
        capture("Design Records", app: app)
        for _ in 0..<5 where !app.buttons["addMeal"].isHittable { app.swipeDown() }
        app.buttons["addMeal"].tap()
        XCTAssertTrue(app.buttons["save.meal"].waitForExistence(timeout: 5))
        capture("Design Meal", app: app)
        app.buttons["닫기"].tap()
        app.tabBars.buttons["꾸미기"].tap()
        XCTAssertTrue(app.buttons["wardrobe.share"].waitForExistence(timeout: 5))
        capture("Design Wardrobe", app: app)
        app.buttons["wardrobe.share"].tap()
        XCTAssertTrue(app.images["share.preview"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["share.export"].isHittable)
        capture("Design Share", app: app)
        app.buttons["닫기"].tap()
        app.tabBars.buttons["설정"].tap()
        XCTAssertTrue(app.buttons["profile.edit"].waitForExistence(timeout: 5))
        capture("Design Profile", app: app)
        app.buttons["profile.edit"].tap()
        XCTAssertTrue(app.textFields["profile.height"].waitForExistence(timeout: 5))
        capture("Design Profile editor", app: app)
        app.buttons["닫기"].tap()
        app.tabBars.buttons["운동"].tap()
        XCTAssertTrue(app.buttons["walk.start"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["walk.start"].isHittable)
        capture("Design Walk", app: app)
        app.segmentedControls["exercise.mode"].buttons["실내"].tap()
        XCTAssertTrue(app.buttons["exercise.indoor.start"].isHittable)
        capture("Design Indoor", app: app)
    }

    func testHomeCharacterReactsAndResets() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset", "-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launch()
        completeOnboardingIfNeeded(in: app)
        let character = app.buttons["care.character"]
        XCTAssertTrue(character.waitForExistence(timeout: 10))
        XCTAssertEqual(character.value as? String, "쉬기")
        capture("Home before character tap", app: app)
        character.tap()
        XCTAssertEqual(character.value as? String, "운동")
        capture("Home character reaction", app: app)
        character.tap()
        XCTAssertEqual(character.value as? String, "걷기")
        let resting = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            character.value as? String == "쉬기"
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [resting], timeout: 5), .completed)
        character.tap()
        app.tabBars.buttons["설정"].tap()
        app.tabBars.buttons["홈"].tap()
        XCTAssertEqual(character.value as? String, "쉬기")
        XCTAssertEqual(app.staticTexts["water.total"].label, "0 mL")
        XCTAssertEqual(app.staticTexts["home.metric.steps"].label, "0보")
    }

    func testDesignAuditAccessibleScreens() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-use-store", "-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["care.character"].waitForExistence(timeout: 15))
        capture("Accessible Home", app: app)
        reveal(app.buttons["addMeal"], in: app)
        app.buttons["addMeal"].tap()
        XCTAssertTrue(app.buttons["save.meal"].waitForExistence(timeout: 5))
        capture("Accessible Meal", app: app)
        app.buttons["닫기"].tap()
        app.tabBars.buttons["꾸미기"].tap()
        XCTAssertTrue(app.buttons["wardrobe.share"].waitForExistence(timeout: 5))
        capture("Accessible Wardrobe", app: app)
        app.buttons["wardrobe.share"].tap()
        XCTAssertTrue(app.images["share.preview"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["share.export"].isHittable)
        capture("Accessible Share", app: app)
        app.buttons["닫기"].tap()
        app.tabBars.buttons["운동"].tap()
        app.segmentedControls["exercise.mode"].buttons["실내"].tap()
        XCTAssertTrue(app.buttons["exercise.indoor.start"].isHittable)
        capture("Accessible Indoor", app: app)
        app.buttons["exercise.indoor.start"].tap()
        XCTAssertTrue(app.buttons["exercise.complete"].waitForExistence(timeout: 10))
        app.buttons["exercise.complete"].tap()
        XCTAssertTrue(app.buttons["exercise.save"].waitForExistence(timeout: 5))
        capture("Accessible Workout completion", app: app)
        app.buttons["exercise.save"].tap()
        XCTAssertTrue(app.buttons["exercise.indoor.start"].waitForExistence(timeout: 10), app.debugDescription)
    }

    func testOnboardingResumeAndShare() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset", "-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launch()
        XCTAssertTrue(app.sliders["onboarding.height"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.keyboards.count, 0)
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        capture("Onboarding first question", app: app)
        app.buttons["onboarding.height.increase"].tap()
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.sliders["onboarding.weight"].waitForExistence(timeout: 5))
        app.buttons["onboarding.weight.increase"].tap()
        capture("Onboarding weight pose", app: app)
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.buttons["onboarding.gender.female"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["--ui-testing-use-store", "-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.gender.female"].waitForExistence(timeout: 10))
        app.buttons["onboarding.back"].tap()
        XCTAssertTrue(app.sliders["onboarding.weight"].waitForExistence(timeout: 5))
        XCTAssertTrue((app.sliders["onboarding.weight"].value as? String ?? "").contains("70.1"))
        app.buttons["onboarding.next"].tap()
        app.buttons["onboarding.gender.female"].tap()
        capture("Onboarding gender pose", app: app)
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.steppers["onboarding.goal"].waitForExistence(timeout: 5))
        capture("Onboarding goal", app: app)
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.buttons["care.share"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["onboarding.next"].exists)
        app.buttons["care.share"].tap()
        XCTAssertTrue(app.images["share.preview"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["share.export"].exists)
        capture("Share card preview", app: app)
        app.buttons["닫기"].tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["care.share"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["onboarding.next"].exists)
        app.tabBars.buttons["설정"].tap()
        XCTAssertTrue(app.staticTexts["성별, 여성"].waitForExistence(timeout: 5))
    }

    func testDestinationSearchAndMapsHandoff() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-use-store", "-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launch()
        completeOnboardingIfNeeded(in: app)
        app.tabBars.buttons["운동"].tap()
        XCTAssertTrue(app.buttons["walk.destination"].waitForExistence(timeout: 8))
        app.buttons["walk.destination"].tap()
        let query = app.textFields["destination.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        query.tap()
        query.typeText("신림역")
        let result = app.buttons["destination.result.0"]
        XCTAssertTrue(result.waitForExistence(timeout: 20), "Live Apple Maps search must return a result or show its real error")
        capture("Destination search results", app: app)
        result.tap()
        XCTAssertTrue(app.buttons["walk.openDirections"].waitForExistence(timeout: 8))
        capture("Selected walking destination", app: app)
        app.buttons["walk.openDirections"].tap()
        let maps = XCUIApplication(bundleIdentifier: "com.apple.Maps")
        XCTAssertTrue(maps.wait(for: .runningForeground, timeout: 15))
        capture("Apple Maps handoff", app: maps)
        app.activate()
        XCTAssertTrue(app.buttons["walk.destination"].waitForExistence(timeout: 10))
    }

    func testHomeSettingsAndIndoorWorkout() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset", "-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launch()
        completeOnboardingIfNeeded(in: app)
        capture("Virtual home initial", app: app)
        app.tabBars.buttons["설정"].tap()
        reveal(app.buttons["profile.edit"], in: app)
        app.buttons["profile.edit"].tap()
        app.buttons["profile.character"].tap()
        let hachiware = app.buttons["하치와레"]
        if hachiware.waitForExistence(timeout: 3) { hachiware.tap() }
        else { app.staticTexts["하치와레"].tap() }
        replace("Mochi", in: app.textFields["profile.name"])
        replace("69", in: app.textFields["profile.weight"])
        reveal(app.textFields["profile.goalTitle"], in: app)
        replace("Every evening 30 minutes", in: app.textFields["profile.goalTitle"])
        app.buttons["profile.keyboardDone"].tap()
        reveal(app.switches["profile.calorieEnabled"], in: app)
        app.switches["profile.calorieEnabled"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        reveal(app.textFields["profile.calorieMinimum"], in: app)
        replace("1800", in: app.textFields["profile.calorieMinimum"])
        replace("2200", in: app.textFields["profile.calorieMaximum"])
        app.buttons["profile.keyboardDone"].tap()
        reveal(app.switches["profile.metric.workoutMinutes"], in: app)
        app.switches["profile.metric.workoutMinutes"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        app.switches["profile.metric.weightChange"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["save.profile"].isEnabled)
        app.buttons["save.profile"].tap()
        let editorClosed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !app.buttons["save.profile"].exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [editorClosed], timeout: 20), .completed,
                       "Settings must save and dismiss: \(app.debugDescription)")
        app.tabBars.buttons["홈"].tap()
        XCTAssertTrue(app.staticTexts["Every evening 30 minutes"].waitForExistence(timeout: 5))
        capture("Hachiware home with selected metrics", app: app)

        app.tabBars.buttons["운동"].tap()
        app.segmentedControls["exercise.mode"].buttons["실내"].tap()
        XCTAssertTrue(app.buttons["exercise.indoor.start"].waitForExistence(timeout: 5))
        app.buttons["exercise.indoor.start"].tap()
        XCTAssertTrue(app.buttons["exercise.complete"].waitForExistence(timeout: 10))
        capture("Indoor workout active", app: app)
        app.terminate()
        app.launchArguments = ["--ui-testing-use-store", "-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launch()
        app.tabBars.buttons["운동"].tap()
        XCTAssertTrue(app.buttons["exercise.complete"].waitForExistence(timeout: 10))
        app.buttons["exercise.complete"].tap()
        replace("20", in: app.textFields["exercise.minutes"])
        replace("30", in: app.textFields["exercise.repetitions"])
        app.buttons["exercise.keyboardDone"].tap()
        reveal(app.buttons["exercise.save"], in: app)
        app.buttons["exercise.save"].tap()
        XCTAssertTrue(app.buttons["exercise.indoor.start"].waitForExistence(timeout: 10))
        app.buttons["exercise.history"].tap()
        XCTAssertTrue(app.staticTexts["20분"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["30회"].exists)
        capture("Recorded indoor workout", app: app)
        app.buttons["닫기"].tap()
        app.tabBars.buttons["홈"].tap()
        app.buttons["care.share"].tap()
        XCTAssertTrue(app.images["share.preview"].waitForExistence(timeout: 15))
        capture("Named character story card", app: app)
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["share.instagramUnavailable"].exists)
        XCTAssertFalse(app.buttons["share.instagram"].exists)
        XCTAssertTrue(app.buttons["share.export"].exists)
    }

    func testWardrobeSlotsAndStory() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-use-store", "-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["꾸미기"].waitForExistence(timeout: 15))
        app.tabBars.buttons["꾸미기"].tap()
        for (category, item) in [("하의", "shorts"), ("신발", "sneakers"), ("액세서리", "bow")] {
            app.segmentedControls["wardrobe.category"].buttons[category].tap()
            let purchase = app.buttons["wardrobe.item.\(item)"]
            reveal(purchase, in: app)
            XCTAssertTrue(purchase.isEnabled)
            purchase.tap()
            let confirm = app.sheets.buttons.matching(NSPredicate(format: "label CONTAINS %@", "P")).firstMatch
            XCTAssertTrue(confirm.waitForExistence(timeout: 5))
            confirm.tap()
            XCTAssertTrue(app.buttons["wardrobe.unequip.\(item == "shorts" ? "bottom" : item == "sneakers" ? "shoes" : "accessory")"].waitForExistence(timeout: 5))
            app.swipeDown()
        }
        capture("Modular outfit equipped", app: app)
        app.buttons["wardrobe.share"].tap()
        XCTAssertTrue(app.images["share.preview"].waitForExistence(timeout: 15))
        capture("Dressed character story card", app: app)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }

    private func replace(_ value: String, in field: XCUIElement) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        let current = field.value as? String ?? ""
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + value)
        XCTAssertEqual(field.value as? String, value)
    }

    private func completeOnboardingIfNeeded(in app: XCUIApplication) {
        guard app.buttons["onboarding.next"].waitForExistence(timeout: 3) else { return }
        if app.sliders["onboarding.height"].exists { app.buttons["onboarding.next"].tap() }
        if app.sliders["onboarding.weight"].waitForExistence(timeout: 2) { app.buttons["onboarding.next"].tap() }
        if app.buttons["onboarding.gender.notSpecified"].waitForExistence(timeout: 2) {
            app.buttons["onboarding.gender.notSpecified"].tap()
            app.buttons["onboarding.next"].tap()
        }
        if app.steppers["onboarding.goal"].waitForExistence(timeout: 2) { app.buttons["onboarding.next"].tap() }
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15))
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func followLocation(in app: XCUIApplication) {
        app.buttons["workout.menu"].tap()
        reveal(app.buttons["walk.follow"], in: app)
        XCTAssertTrue(app.buttons["walk.follow"].waitForExistence(timeout: 5))
        app.buttons["walk.follow"].tap()
        XCTAssertTrue(app.buttons["workout.menu"].waitForExistence(timeout: 5))
    }

    private func enter(_ value: String, into field: XCUIElement) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(value)
    }
}
