import Foundation
import Testing
@testable import REPickShared

@Suite struct NutritionMissionCostumeTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    private func date(_ day: Int = 1) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: String(format: "2026-10-%02dT12:00:00Z", day)))
    }

    private func state(minimum: Int? = nil, maximum: Int? = nil, points: Int = 0) throws -> UsagiState {
        var state = UsagiState(now: try date(), calendar: calendar)
        try state.setProfile(heightCM: 170, weightKG: 70, targetWeightKG: 65, goalSteps: 10_000)
        if minimum != nil || maximum != nil {
            var preferences = state.preferences
            preferences.calorieMinimum = minimum
            preferences.calorieMaximum = maximum
            try state.setPreferences(preferences)
        }
        if points != 0 {
            var json = try json(state)
            json["points"] = points
            state = try decode(json)
        }
        return state
    }

    private func json(_ state: UsagiState) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
    }

    private func decode(_ json: [String: Any]) throws -> UsagiState {
        let state = try JSONDecoder().decode(UsagiState.self, from: JSONSerialization.data(withJSONObject: json))
        try state.validate()
        return state
    }

    private func addThreeMeals(to state: inout UsagiState, day: Int = 1, calories: Int = 300) throws {
        for kind in [MealKind.breakfast, .lunch, .dinner] {
            try state.addMeal(name: kind.rawValue, calories: calories, source: .manual,
                              now: date(day), kind: kind, calendar: calendar)
        }
    }

    @Test func missingRangeAndMissingRecordsStayNeutral() throws {
        var state = try state()
        #expect(state.nutritionStatus == .unconfigured)
        #expect(state.nutritionMood == .neutral)
        #expect(state.bodyScale == 1 && state.targetBodyScale == 1)
        var preferences = state.preferences
        preferences.calorieMinimum = 900
        preferences.calorieMaximum = 1_200
        try state.setPreferences(preferences)
        #expect(state.dailyCalorieMinimum == 900 && state.dailyCalorieMaximum == 1_200)
        #expect(state.nutritionStatus == .unrecorded && state.nutritionMood == .neutral)
        #expect(state.bodyScale == 1)
        try state.addMeal(name: "Breakfast", calories: 300, source: .manual, now: date(), kind: .breakfast, calendar: calendar)
        #expect(state.nutritionStatus == .below && state.nutritionMood == .lowEnergy)
        #expect(state.bodyScale == 1)
    }

    @Test func firstRangeAppliesImmediatelyButLaterEditsWaitForRollover() throws {
        var state = try state()
        try state.addMeal(name: "Meal", calories: 1_000, source: .manual, now: date(), calendar: calendar)
        var preferences = state.preferences
        preferences.calorieMinimum = 900
        preferences.calorieMaximum = 1_200
        try state.setPreferences(preferences)
        #expect(state.nutritionStatus == .within && state.nutritionMood == .sparkling)
        preferences.calorieMinimum = 1_500
        preferences.calorieMaximum = 2_000
        try state.setPreferences(preferences)
        #expect(state.dailyCalorieMinimum == 900 && state.dailyCalorieMaximum == 1_200)
        #expect(state.calorieRangeChangesTomorrow)
        #expect(state.nutritionStatus == .within)
        state = try decode(json(state))
        #expect(state.dailyCalorieMinimum == 900 && state.calorieRangeChangesTomorrow)
        state.rollover(now: try date(2), calendar: calendar)
        #expect(state.dailyCalorieMinimum == 1_500 && state.dailyCalorieMaximum == 2_000)
        #expect(!state.calorieRangeChangesTomorrow)
        #expect(state.nutritionStatus == .unrecorded && state.nutritionMood == .neutral)
        #expect(state.totalFoodCalories == 1_000 && state.mealHistory.count == 1)
        preferences.calorieMinimum = nil
        preferences.calorieMaximum = nil
        try state.setPreferences(preferences)
        #expect(state.dailyCalorieMaximum == 2_000 && state.calorieRangeChangesTomorrow)
        state.rollover(now: try date(3), calendar: calendar)
        #expect(state.dailyCalorieMinimum == nil && state.dailyCalorieMaximum == nil)
        #expect(state.nutritionStatus == .unconfigured)
    }

    @Test(arguments: [900, 1_200]) func calorieBoundsAreInclusive(calories: Int) throws {
        var state = try state(minimum: 900, maximum: 1_200)
        try state.addMeal(name: "Meal", calories: calories, source: .manual, now: date(), calendar: calendar)
        #expect(state.nutritionStatus == .within && state.nutritionMood == .sparkling)
        #expect(state.bodyScale == 1)
    }

    @Test func appearanceUsesOnlyTodaysUpperOvershootAndPreservesRealStats() throws {
        var state = try state(minimum: 900, maximum: 1_200)
        let profile = state.profile
        try state.addMeal(name: "Meal", calories: 1_800, source: .manual, now: date(), calendar: calendar)
        #expect(state.nutritionStatus == .above && state.nutritionMood == .neutral)
        #expect(abs(state.bodyScale - 1.3) < 0.000_001)
        let session = try state.startWorkout(mode: .indoor, now: date(), activity: .strength)
        try state.finishWorkout(durationMinutes: 30, calories: 600, now: date().addingTimeInterval(1_800),
                                sessionID: session.id, calendar: calendar)
        #expect(abs(state.bodyScale - 1.3) < 0.000_001)
        #expect(state.profile == profile && state.totalFoodCalories == 1_800)
        #expect(state.totalExerciseCalories == 600 && state.totalStrengthMinutes == 30 && state.muscleLevel == 0.1)
        try state.addMeal(name: "Second meal", calories: 4_000, source: .manual, now: date(), calendar: calendar)
        #expect(state.bodyScale == 1.6)
        state.rollover(now: try date(2), calendar: calendar)
        #expect(state.bodyScale == 1 && state.nutritionMood == .neutral)
        #expect(state.totalFoodCalories == 5_800 && state.mealHistory.count == 2)
        #expect(state.profile == profile && state.totalExerciseCalories == 600 && state.totalStrengthMinutes == 30)
        try state.validate()
    }

    @Test func mealKindsAreOptionalAndRetriesCannotRetagExistingMeals() throws {
        var state = try state()
        let id = UUID()
        try state.addMeal(name: "Meal", calories: 300, source: .manual, now: date(), id: id, kind: .breakfast, calendar: calendar)
        let before = state
        try state.addMeal(name: "Meal", calories: 300, source: .manual, now: date().addingTimeInterval(60), id: id, kind: .breakfast, calendar: calendar)
        #expect(state == before)
        #expect(throws: (any Error).self) {
            try state.addMeal(name: "Meal", calories: 300, source: .manual, now: date(), id: id, kind: .dinner, calendar: calendar)
        }
        #expect(state == before)
        let legacy = try MealEntry(name: "Legacy", calories: 300, source: .manual, recordedAt: date())
        var encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
        encoded.removeValue(forKey: "kind")
        let decoded = try JSONDecoder().decode(MealEntry.self, from: JSONSerialization.data(withJSONObject: encoded))
        #expect(decoded.kind == nil && decoded == legacy)
    }

    @Test func threeMealsCountsDistinctMainMealTypesOnly() throws {
        var state = try state(minimum: 900, maximum: 2_000)
        for kind in [nil, MealKind.snack, .breakfast, .breakfast] {
            try state.addMeal(name: "Meal", calories: 100, source: .manual, now: date(), kind: kind, calendar: calendar)
        }
        #expect(state.missionProgress(for: .threeMeals) == 1)
        #expect(state.missionTarget(for: .threeMeals) == 3)
        try state.addMeal(name: "Lunch", calories: 300, source: .manual, now: date(), kind: .lunch, calendar: calendar)
        #expect(state.missionProgress(for: .threeMeals) == 2)
        try state.addMeal(name: "Dinner", calories: 300, source: .manual, now: date(), kind: .dinner, calendar: calendar)
        #expect(state.missionProgress(for: .threeMeals) == 3)
        #expect(state.missionProgress(for: .calorieRange) == 0)
        try state.validate()
    }

    @Test func claimsRequireAttendanceAndCompletionAndAwardEachKindOnce() throws {
        var state = try state(minimum: 900, maximum: 1_200)
        try addThreeMeals(to: &state)
        try state.recordStairSteps(5, now: date(), calendar: calendar)
        try state.confirmFoodDay(now: date(), calendar: calendar)
        let before = state
        #expect(throws: (any Error).self) { try state.claimMission(.stairs, now: date(), calendar: calendar) }
        #expect(state == before)
        try state.checkIn(now: date(), calendar: calendar)
        for kind in DailyMissionKind.allCases {
            #expect(try state.claimMission(kind, now: date(), calendar: calendar) == 5)
            #expect(state.missionRewardClaimed(kind))
            #expect(state.missionRewardPoints == 5)
            let claimed = state
            #expect(try state.claimMission(kind, now: date(), calendar: calendar) == 0)
            #expect(state == claimed)
        }
        #expect(state.points == 15 && state.missionRewardStreak == 1)
        try state.validate()
        var incomplete = try self.state()
        try incomplete.checkIn(now: date(), calendar: calendar)
        let unchecked = incomplete
        for kind in DailyMissionKind.allCases {
            #expect(throws: (any Error).self) { try incomplete.claimMission(kind, now: date(), calendar: calendar) }
            #expect(incomplete == unchecked)
        }
    }

    @Test func foodDayNeedsRangeAndThreeKindsThenSealsCompletionWithoutHidingNewFood() throws {
        var unconfigured = try state()
        try addThreeMeals(to: &unconfigured)
        let original = unconfigured
        #expect(throws: (any Error).self) { try unconfigured.confirmFoodDay(now: date(), calendar: calendar) }
        #expect(unconfigured == original)
        var state = try state(minimum: 900, maximum: 1_200)
        try state.addMeal(name: "Only breakfast", calories: 900, source: .manual, now: date(), kind: .breakfast, calendar: calendar)
        let missingKinds = state
        #expect(throws: (any Error).self) { try state.confirmFoodDay(now: date(), calendar: calendar) }
        #expect(state == missingKinds)
        try state.addMeal(name: "Lunch", calories: 100, source: .manual, now: date(), kind: .lunch, calendar: calendar)
        try state.addMeal(name: "Dinner", calories: 100, source: .manual, now: date(), kind: .dinner, calendar: calendar)
        try state.checkIn(now: date(), calendar: calendar)
        try state.confirmFoodDay(now: date(), calendar: calendar)
        #expect(state.missionProgress(for: .calorieRange) == 1)
        #expect(state.missionTarget(for: .calorieRange) == 1)
        #expect(try state.claimMission(.calorieRange, now: date(), calendar: calendar) == 5)
        try state.addMeal(name: "Later snack", calories: 500, source: .manual, now: date(), kind: .snack, calendar: calendar)
        #expect(state.nutritionStatus == .above && state.bodyScale > 1)
        #expect(state.missionProgress(for: .calorieRange) == 1 && state.missionRewardClaimed(.calorieRange))
        #expect(try state.claimMission(.calorieRange, now: date(), calendar: calendar) == 0)
        #expect(state.points == 5 && state.totalFoodCalories == 1_600)
        state = try decode(json(state))
        #expect(state.missionRewardClaimed(.calorieRange) && state.nutritionStatus == .above)
    }

    @Test func nextDayRewardEscalatesOnlyAfterConsecutiveQualifiedDays() throws {
        var state = try state()
        try state.checkIn(now: date(), calendar: calendar)
        try state.recordStairSteps(5, now: date(), calendar: calendar)
        #expect(try state.claimMission(.stairs, now: date(), calendar: calendar) == 5)
        #expect(state.missionRewardPoints == 5 && state.missionRewardStreak == 1)
        state.rollover(now: try date(2), calendar: calendar)
        #expect(state.missionRewardPoints == 10 && !state.missionRewardClaimed(.stairs))
        #expect(state.missionProgress(for: .stairs) == 0)
        try state.checkIn(now: date(2), calendar: calendar)
        try state.recordStairSteps(5, now: date(2), calendar: calendar)
        #expect(try state.claimMission(.stairs, now: date(2), calendar: calendar) == 10)
        #expect(state.missionRewardPoints == 10 && state.missionRewardStreak == 2)
        state = try decode(json(state))
        state.rollover(now: try date(3), calendar: calendar)
        #expect(state.missionRewardPoints == 15)
        try state.checkIn(now: date(3), calendar: calendar)
        try state.recordStairSteps(5, now: date(3), calendar: calendar)
        state.rollover(now: try date(4), calendar: calendar)
        #expect(state.missionRewardPoints == 5 && state.missionRewardStreak == 0)
        try state.checkIn(now: date(4), calendar: calendar)
        try state.recordStairSteps(5, now: date(4), calendar: calendar)
        #expect(try state.claimMission(.stairs, now: date(4), calendar: calendar) == 5)
        state.rollover(now: try date(6), calendar: calendar)
        #expect(state.missionRewardPoints == 5 && state.missionRewardStreak == 0)
        #expect(state.points == 20)
        try state.validate()
    }

    @Test func manualStairTotalsAreMonotonicAndInvalidOrBackdatedActionsAreAtomic() throws {
        var state = try state()
        try state.recordSteps(10_000)
        #expect(state.missionProgress(for: .stairs) == 0)
        #expect(state.missionTarget(for: .stairs) == 5)
        try state.recordStairSteps(4, now: date(), calendar: calendar)
        try state.recordStairSteps(2, now: date(), calendar: calendar)
        #expect(state.missionProgress(for: .stairs) == 4)
        let before = state
        #expect(throws: (any Error).self) { try state.recordStairSteps(-1, now: date(), calendar: calendar) }
        #expect(throws: (any Error).self) { try state.recordStairSteps(Int.max, now: date(), calendar: calendar) }
        #expect(state == before)
        try state.recordStairSteps(5, now: date(2), calendar: calendar)
        let tomorrow = state
        #expect(state.daily.day == "2026-10-02")
        #expect(throws: (any Error).self) { try state.recordStairSteps(6, now: date(), calendar: calendar) }
        #expect(throws: (any Error).self) { try state.confirmFoodDay(now: date(), calendar: calendar) }
        #expect(throws: (any Error).self) { try state.claimMission(.stairs, now: date(), calendar: calendar) }
        #expect(state == tomorrow)
    }

    @Test func missionWalletOverflowDoesNotMarkClaimOrAdvanceStreak() throws {
        var state = try state(points: Int.max)
        try state.checkIn(now: date(), calendar: calendar)
        try state.recordStairSteps(5, now: date(), calendar: calendar)
        let before = state
        #expect(throws: (any Error).self) { try state.claimMission(.stairs, now: date(), calendar: calendar) }
        #expect(state == before)
        #expect(!state.missionRewardClaimed(.stairs) && state.missionRewardStreak == 0)
    }

    @Test func costumeOwnershipIsPerCharacterAndLegacyEquipmentRemainsAvailable() throws {
        var state = try state(points: 2_000)
        try state.buyOutfit(.student)
        try state.buyItem(.bow)
        let usagi = CharacterCostume(character: .usagi, style: .pajamas)
        let hachiware = CharacterCostume(character: .hachiware, style: .pajamas)
        #expect(usagi.id != hachiware.id && CostumeStyle.pajamas.price == 500)
        try state.buyCostume(usagi)
        #expect(state.currentCostume == .pajamas)
        #expect(state.ownedOutfits.contains(.student) && state.ownedItems.contains(.bow))
        #expect(state.equippedOutfit == .student && state.equippedItems.contains(.bow))
        var preferences = state.preferences
        preferences.character = .hachiware
        try state.setPreferences(preferences)
        #expect(state.currentCostume == nil && !state.ownedCostumes.contains(hachiware))
        try state.buyCostume(hachiware)
        #expect(state.currentCostume == .pajamas && state.ownedCostumes.count == 2)
        try state.equip(.student)
        #expect(state.currentCostume == .pajamas && state.ownedCostumes.contains(hachiware))
        preferences.character = .usagi
        try state.setPreferences(preferences)
        #expect(state.currentCostume == .pajamas)
        try state.equipItem(.bow)
        #expect(state.currentCostume == .pajamas && state.ownedCostumes.contains(usagi))
        try state.equipCostume(usagi)
        #expect(state.currentCostume == .pajamas)
        #expect(state.points == 300)
        state = try decode(json(state))
        #expect(state.ownedCostumes.count == 2 && state.currentCostume == .pajamas)
        try state.validate()
    }

    @Test func layeredWardrobePreservesOtherCategoriesThroughPurchaseEquipAndRemoval() throws {
        var state = try state(points: 3_000)
        let costume = CharacterCostume(character: .usagi, style: .gyaru)
        try state.buyCostume(costume)
        try state.buyOutfit(.student)
        try state.buyItem(.shorts)
        try state.buyItem(.sneakers)
        try state.buyItem(.bow)
        #expect(state.currentCostume == .gyaru && state.equippedOutfit == .student)
        #expect(Set(state.equippedItems) == [.shorts, .sneakers, .bow])
        #expect(state.points == 1_250)

        try state.buyItem(.skirt)
        try state.equipItem(.shorts)
        try state.equip(.basic)
        try state.equip(.student)
        try state.equipCostume(costume)
        #expect(state.currentCostume == .gyaru && state.equippedOutfit == .student)
        #expect(Set(state.equippedItems) == [.shorts, .sneakers, .bow])
        #expect(state.points == 950)
        state = try decode(json(state))
        #expect(state.currentCostume == .gyaru && state.equippedOutfit == .student)
        #expect(Set(state.equippedItems) == [.shorts, .sneakers, .bow])

        state.unequipItem(in: .bottom)
        #expect(state.currentCostume == .gyaru && state.equippedOutfit == .student)
        #expect(Set(state.equippedItems) == [.sneakers, .bow])
        state.unequipItem(in: .top)
        #expect(state.currentCostume == .gyaru && state.equippedOutfit == .basic)
        state.unequipCostume()
        #expect(state.currentCostume == nil && state.ownedCostumes.contains(costume))
        #expect(Set(state.equippedItems) == [.sneakers, .bow])
        #expect(state.points == 950)
        try state.validate()
    }

    @Test func layeredWardrobeSurvivesCostumeAndLegacyGachaRewards() throws {
        var state = try state(points: 2_000)
        try state.buyOutfit(.student)
        try state.buyItem(.sneakers)
        try state.buyItem(.glasses)
        try state.recordSteps(10_000)
        let id = UUID()
        let receipt = try state.openGacha(id: id, randomIndex: 0, payment: .points)
        #expect(state.currentCostume == .mermaidIsland && state.equippedOutfit == .student)
        #expect(Set(state.equippedItems) == [.sneakers, .glasses])
        let afterDraw = state
        #expect(try state.openGacha(id: id, randomIndex: 1, payment: .points) == receipt)
        #expect(state == afterDraw)
        let outfit = try state.drawOutfit(randomIndex: 0)
        #expect(state.currentCostume == .mermaidIsland && state.equippedOutfit == outfit)
        #expect(Set(state.equippedItems) == [.sneakers, .glasses])
        try state.validate()
    }

    @Test func costumePurchaseAndEquipFailuresLeaveWalletAndWardrobeUntouched() throws {
        var state = try state()
        let item = CharacterCostume(character: .usagi, style: .gyaru)
        let before = state
        #expect(throws: (any Error).self) { try state.buyCostume(item) }
        #expect(throws: (any Error).self) { try state.equipCostume(item) }
        #expect(state == before)
        state = try self.state(points: 500)
        try state.buyCostume(item)
        let owned = state
        #expect(throws: (any Error).self) { try state.buyCostume(item) }
        #expect(state == owned && state.points == 0)
    }

    @Test func gachaUsesCapturedCharacterPoolAndRetriesPreserveOriginalReceipt() throws {
        var state = try state(points: 1_000)
        try state.recordSteps(10_000)
        let id = UUID()
        let receipt = try state.openGacha(id: id, randomIndex: 0, payment: .points, character: .chiikawa)
        let costume = try #require(receipt.costume)
        #expect(costume.character == .chiikawa && costume.style == .mermaidIsland)
        #expect(receipt.rewardName == costume.style.name && receipt.outfit == nil)
        #expect(state.ownedCostumes.contains(costume) && !receipt.wasDuplicate)
        #expect(state.points == 900 && state.daily.draws == 1)
        #expect(state.ownedOutfits == [.basic])
        state = try decode(json(state))
        let saved = state
        let retry = try state.openGacha(id: id, randomIndex: 2, payment: .free, character: .hachiware)
        #expect(retry == receipt && state == saved)
        let duplicate = try state.openGacha(id: UUID(), randomIndex: 0, payment: .points, character: .chiikawa)
        #expect(duplicate.wasDuplicate && state.points == 850 && state.daily.draws == 2)
        #expect(state.ownedCostumes.filter { $0 == costume }.count == 1)
        let other = try state.openGacha(id: UUID(), randomIndex: 0, payment: .points, character: .hachiware)
        #expect(!other.wasDuplicate && other.costume?.character == .hachiware)
        #expect(state.points == 750)
        let beforeInvalid = state
        #expect(throws: (any Error).self) { try state.openGacha(id: UUID(), randomIndex: 3, payment: .points) }
        #expect(state == beforeInvalid)
        try state.validate()
    }

    @Test func legacyReceiptDecodesAndOldDrawAPIStillAwardsOldOutfits() throws {
        let id = UUID()
        let legacy: [String: Any] = ["id": id.uuidString, "outfit": "student", "wasDuplicate": false, "payment": "points"]
        let receipt = try JSONDecoder().decode(GachaReceipt.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(receipt.outfit == .student && receipt.costume == nil && receipt.rewardName == Outfit.student.name)
        var state = try state(points: 1_000)
        try state.recordSteps(10_000)
        #expect(try state.drawOutfit(randomIndex: 0) == .student)
        #expect(state.ownedOutfits.contains(.student) && state.equippedOutfit == .student)
        #expect(state.ownedCostumes.isEmpty && state.points == 900)
        var stored = try json(state)
        stored["gachaReceipts"] = [legacy]
        let restored = try decode(stored)
        #expect(restored.gachaReceipts.first == receipt && restored.ownedOutfits == state.ownedOutfits)
    }

    @Test func legacyStateWithoutNewFieldsKeepsInventoryAndStartsMissionsUnclaimed() throws {
        var state = try state(minimum: 900, maximum: 1_200, points: 1_000)
        try state.buyOutfit(.office)
        try state.buyItem(.bow)
        try state.addMeal(name: "Legacy meal", calories: 1_000, source: .manual, now: date(), calendar: calendar)
        var legacy = try json(state)
        for key in ["dailyNutrition", "hasConfiguredCalorieRange", "dailyMissions", "missionRewards", "ownedCostumes", "equippedCostumes"] {
            legacy.removeValue(forKey: key)
        }
        var daily = try #require(legacy["daily"] as? [String: Any])
        var meals = try #require(daily["meals"] as? [[String: Any]])
        meals[0].removeValue(forKey: "kind")
        daily["meals"] = meals
        legacy["daily"] = daily
        legacy["mealHistory"] = meals
        let restored = try decode(legacy)
        #expect(restored.points == 300 && restored.totalFoodCalories == 1_000)
        #expect(restored.ownedOutfits == state.ownedOutfits && restored.equippedOutfit == .office)
        #expect(restored.ownedItems == [.bow] && restored.equippedItems == [.bow])
        #expect(restored.ownedCostumes.isEmpty && restored.currentCostume == nil)
        #expect(restored.daily.meals.first?.kind == nil)
        #expect(restored.dailyCalorieMinimum == 900 && restored.dailyCalorieMaximum == 1_200)
        #expect(restored.nutritionStatus == .within && restored.nutritionMood == .sparkling)
        #expect(restored.missionRewardPoints == 5 && restored.missionRewardStreak == 0)
        for kind in DailyMissionKind.allCases {
            #expect(restored.missionProgress(for: kind) == 0 && !restored.missionRewardClaimed(kind))
        }
    }

    @Test(arguments: ["dailyNutrition", "hasConfiguredCalorieRange", "dailyMissions", "missionRewards", "ownedCostumes", "equippedCostumes"])
    func explicitNullNewRequiredSaveFieldsAreRejected(key: String) throws {
        var invalid = try json(state())
        invalid[key] = NSNull()
        #expect(throws: (any Error).self) { try decode(invalid) }
    }

    @Test func invalidMissionLedgerAndCostumeOwnershipAreRejected() throws {
        let original = try json(state())
        var invalid = original
        var missions = try #require(invalid["dailyMissions"] as? [String: Any])
        missions["stairSteps"] = -1
        invalid["dailyMissions"] = missions
        #expect(throws: (any Error).self) { try decode(invalid) }
        invalid = original
        missions = try #require(invalid["dailyMissions"] as? [String: Any])
        missions["claimed"] = ["stairs", "stairs"]
        invalid["dailyMissions"] = missions
        #expect(throws: (any Error).self) { try decode(invalid) }
        invalid = original
        invalid["equippedCostumes"] = [["character": "usagi", "style": "gyaru"]]
        #expect(throws: (any Error).self) { try decode(invalid) }
    }

    @Test func localCalendarMidnightResetsMissionProgressAndAdvancesRewardOnce() throws {
        var seoul = calendar
        seoul.timeZone = try #require(TimeZone(identifier: "Asia/Seoul"))
        let beforeMidnight = try #require(ISO8601DateFormatter().date(from: "2026-10-01T14:59:00Z"))
        let afterMidnight = beforeMidnight.addingTimeInterval(120)
        var state = UsagiState(now: beforeMidnight, calendar: seoul)
        try state.setProfile(heightCM: 170, weightKG: 70, targetWeightKG: 65, goalSteps: 2_000)
        try state.checkIn(now: beforeMidnight, calendar: seoul)
        try state.recordStairSteps(5, now: beforeMidnight, calendar: seoul)
        #expect(try state.claimMission(.stairs, now: beforeMidnight, calendar: seoul) == 5)
        state.rollover(now: afterMidnight, calendar: seoul)
        #expect(state.daily.day == "2026-10-02" && state.missionRewardPoints == 10)
        #expect(state.missionProgress(for: .stairs) == 0 && !state.missionRewardClaimed(.stairs))
        let rolledOver = state
        state.rollover(now: afterMidnight.addingTimeInterval(60), calendar: seoul)
        #expect(state == rolledOver)
        #expect(throws: (any Error).self) { try state.claimMission(.stairs, now: beforeMidnight, calendar: seoul) }
        #expect(state == rolledOver)
    }

    @Test func missionStreakAndEscalatingRewardSurviveAttendanceHistoryRetention() throws {
        var state = try state()
        let start = try date()
        for index in 0..<368 {
            let now = start.addingTimeInterval(Double(index) * 86_400)
            try state.checkIn(now: now, calendar: calendar)
            try state.recordStairSteps(5, now: now, calendar: calendar)
            #expect(try state.claimMission(.stairs, now: now, calendar: calendar) == (index + 1) * 5)
        }
        #expect(state.attendance.days.count == 366 && state.missionRewardStreak == 368)
        #expect(state.points == 5 * 368 * 369 / 2)
        state = try decode(json(state))
        state.rollover(now: start.addingTimeInterval(368 * 86_400), calendar: calendar)
        #expect(state.missionRewardPoints == 1_845 && state.missionRewardStreak == 368)
        try state.validate()
    }

    @Test func rewardAmountMustMatchItsQualifiedDayLedger() throws {
        var state = try state()
        for stage in 0..<3 {
            if stage == 1 {
                try state.checkIn(now: date(), calendar: calendar)
                try state.recordStairSteps(5, now: date(), calendar: calendar)
                _ = try state.claimMission(.stairs, now: date(), calendar: calendar)
            } else if stage == 2 {
                state.rollover(now: try date(2), calendar: calendar)
            }
            var invalid = try json(state)
            var missions = try #require(invalid["dailyMissions"] as? [String: Any])
            missions["rewardPoints"] = 15
            invalid["dailyMissions"] = missions
            #expect(throws: (any Error).self) { try decode(invalid) }
        }
    }

    @Test func confirmedFoodSnapshotMustMatchTheFrozenRangeAndRecordedCalories() throws {
        var state = try state(minimum: 900, maximum: 1_200)
        try addThreeMeals(to: &state)
        try state.confirmFoodDay(now: date(), calendar: calendar)
        let original = try json(state)
        let missions = try #require(original["dailyMissions"] as? [String: Any])
        #expect(missions["confirmedFoodCalories"] as? Int == 900)
        for invalidSnapshot in [800, 1_300, 1_100, NSNull()] as [Any] {
            var invalid = original
            var invalidMissions = missions
            invalidMissions["confirmedFoodCalories"] = invalidSnapshot
            invalid["dailyMissions"] = invalidMissions
            #expect(throws: (any Error).self) { try decode(invalid) }
        }
    }

    @Test func newCostumeFreeDrawKeepsPaymentAndDailyQuotaRules() throws {
        var fixture = try json(state())
        fixture["freeDraws"] = 1
        var state = try decode(fixture)
        let receipt = try state.openGacha(id: UUID(), randomIndex: 2, payment: .free)
        #expect(receipt.costume?.style == .gyaru && receipt.payment == .free)
        #expect(state.freeDraws == 0 && state.daily.draws == 0 && state.points == 0)
        let spent = state
        #expect(throws: (any Error).self) { try state.openGacha(id: UUID(), randomIndex: 1, payment: .free) }
        #expect(throws: (any Error).self) { try state.openGacha(id: UUID(), randomIndex: 1, payment: .points) }
        #expect(state == spent)
        try state.recordSteps(10_000)
        try state.claimReward()
        for index in 0..<5 {
            _ = try state.openGacha(id: UUID(), randomIndex: index % 3, payment: .points)
        }
        let capped = state
        #expect(state.daily.draws == 5)
        #expect(throws: (any Error).self) { try state.openGacha(id: UUID(), randomIndex: 0, payment: .points) }
        #expect(state == capped)
        try state.validate()
    }

    @Test func missionAndCostumePersistenceSurviveFailedSaveAndRetry() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "state.json")
        let disk = LocalSaveStore(fileURL: url)
        var state = try state(points: 500)
        try state.checkIn(now: date(), calendar: calendar)
        try state.recordStairSteps(5, now: date(), calendar: calendar)
        try await disk.save(state)
        let before = try Data(contentsOf: url)
        #expect(try state.claimMission(.stairs, now: date(), calendar: calendar) == 5)
        try state.buyCostume(CharacterCostume(character: .usagi, style: .gyaru))
        let invalidDisk = LocalSaveStore(fileURL: url.appending(path: "cannot-save.json"))
        await #expect(throws: (any Error).self) { try await invalidDisk.save(state) }
        #expect(try Data(contentsOf: url) == before)
        let old = try await disk.load(now: date(), calendar: calendar)
        #expect(!old.missionRewardClaimed(.stairs) && old.ownedCostumes.isEmpty && old.points == 500)
        try await disk.save(state)
        var restored = try await disk.load(now: date(), calendar: calendar)
        #expect(restored == state && restored.currentCostume == .gyaru)
        #expect(try restored.claimMission(.stairs, now: date(), calendar: calendar) == 0)
        #expect(restored.points == 5)
    }
}
