import Foundation
import Testing
@testable import REPickShared

private let featureDay = Date(timeIntervalSince1970: 1_792_800_000)

private var featureCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar
}

private func featureState() throws -> UsagiState {
    var state = UsagiState(now: featureDay, calendar: featureCalendar)
    try state.setProfile(heightCM: 170, weightKG: 70, targetWeightKG: 65, goalSteps: 10_000)
    return state
}

private func fundedFeatureState() throws -> UsagiState {
    var state = try featureState()
    for day in 0..<3 {
        state.rollover(now: featureDay.addingTimeInterval(Double(day) * 86_400), calendar: featureCalendar)
        try state.recordSteps(10_000)
        try state.claimReward()
    }
    return state
}

private func legacyFeatureState() throws -> UsagiState {
    let data = Data(#"{"schemaVersion":1,"profile":{"heightCM":170,"weightKG":70,"targetWeightKG":65},"daily":{"day":"2026-10-24","goalSteps":6000,"steps":6500,"rewardClaimed":true,"draws":1,"waterML":250,"meals":[]},"points":200,"ownedOutfits":["basic","student"],"equippedOutfit":"student","totalFoodCalories":0}"#.utf8)
    return try JSONDecoder().decode(UsagiState.self, from: data)
}

@Test func watchSnapshotOmitsHistoryWithoutChangingPhoneStateOrCurrentWorkout() throws {
    var state = try fundedFeatureState()
    var preferences = state.preferences
    preferences.character = .chiikawa
    preferences.name = "치이"
    try state.setPreferences(preferences)
    try state.buyItem(.bow)
    try state.buyOutfit(.student)
    try state.addWater(250)
    try state.addMeal(name: "밥", calories: 300, source: .manual, now: featureDay)
    let completed = try state.startWorkout(mode: .outdoor, now: featureDay)
    try state.finishWorkout(durationMinutes: 20, now: featureDay.addingTimeInterval(1_200), sessionID: completed.id)
    try state.startWorkout(mode: .indoor, now: featureDay.addingTimeInterval(1_800))
    let original = state
    let snapshot = state.watchSnapshot()
    try snapshot.validate()
    #expect(state == original)
    #expect(state.workouts.count == 1)
    #expect(snapshot.workouts.isEmpty)
    #expect(snapshot.activeWorkout == state.activeWorkout)
    #expect(snapshot.profile == state.profile)
    #expect(snapshot.initialWeightKG == state.initialWeightKG)
    #expect(snapshot.preferences == state.preferences)
    #expect(snapshot.ownedOutfits == state.ownedOutfits)
    #expect(snapshot.equippedOutfit == state.equippedOutfit)
    #expect(snapshot.ownedItems == state.ownedItems)
    #expect(snapshot.equippedItems == state.equippedItems)
    #expect(snapshot.daily == state.daily)
    #expect(snapshot.points == state.points)
    #expect(snapshot.totalFoodCalories == state.totalFoodCalories)
}

@Test func companionExpansionPreservesLegacyProgressWithoutInventingWeightHistory() throws {
    let state = try legacyFeatureState()
    try state.validate()
    #expect(state.points == 200)
    #expect(state.ownedOutfits == [.basic, .student])
    #expect(state.equippedOutfit == .student)
    #expect(state.daily.steps == 6_500)
    #expect(state.daily.rewardClaimed)
    #expect(state.daily.draws == 1)
    #expect(state.daily.waterML == 250)
    #expect(state.preferences.character == .usagi)
    #expect(!state.preferences.voiceEnabled)
    #expect(state.initialWeightKG == nil)
    #expect(state.weightChangeKG == nil)
    #expect(state.ownedItems.isEmpty && state.equippedItems.isEmpty)
    #expect(state.activeWorkout == nil && state.workouts.isEmpty)
    let restored = try JSONDecoder().decode(UsagiState.self, from: JSONEncoder().encode(state))
    #expect(restored == state)
}

@Test func companionPreferencesRoundTripAndDoNotChangeRecordedBodyMeasurements() throws {
    var state = try featureState()
    let profile = state.profile
    var preferences = CompanionPreferences()
    preferences.name = "  하치  "
    preferences.character = .hachiware
    preferences.goalTitle = "  매일 산책하기  "
    preferences.calorieMinimum = 1_800
    preferences.calorieMaximum = 2_400
    preferences.homeMetrics = [.workoutMinutes, .weightChange, .water]
    try state.setPreferences(preferences)
    #expect(state.preferences.name == "하치")
    #expect(state.preferences.goalTitle == "매일 산책하기")
    #expect(state.preferences.homeMetrics == [.workoutMinutes, .weightChange, .water])
    #expect(state.profile == profile)
    let restored = try JSONDecoder().decode(UsagiState.self, from: JSONEncoder().encode(state))
    try restored.validate()
    #expect(restored == state)
}

@Test(arguments: ["blankName", "longName", "reversedCalories", "partialCalories", "negativeCalories", "excessiveCalories", "emptyMetrics", "duplicateMetrics"])
func invalidCompanionPreferencesDoNotChangeState(invalid: String) throws {
    var state = try featureState()
    var preferences = state.preferences
    switch invalid {
    case "blankName": preferences.name = " \n "
    case "longName": preferences.name = String(repeating: "가", count: 300)
    case "reversedCalories": preferences.calorieMinimum = 2_400; preferences.calorieMaximum = 1_800
    case "partialCalories": preferences.calorieMinimum = 1_800
    case "negativeCalories": preferences.calorieMinimum = -1; preferences.calorieMaximum = 2_000
    case "excessiveCalories": preferences.calorieMinimum = 1; preferences.calorieMaximum = 10_001
    case "emptyMetrics": preferences.homeMetrics = []
    default: preferences.homeMetrics = [.water, .water]
    }
    let original = state
    #expect(throws: DomainError.self) { try state.setPreferences(preferences) }
    #expect(state == original)
}

@Test func weightComparisonUsesFirstAvailableRecordedWeightAndSurvivesGoalEdits() throws {
    var fresh = try featureState()
    #expect(fresh.initialWeightKG == 70)
    try fresh.setProfile(heightCM: 172, weightKG: 69, targetWeightKG: 64, goalSteps: 8_000)
    #expect(fresh.initialWeightKG == 70)
    #expect(fresh.weightChangeKG == -1)

    var legacy = try legacyFeatureState()
    try legacy.setProfile(heightCM: 170, weightKG: 71, targetWeightKG: 65, goalSteps: 6_000)
    #expect(legacy.initialWeightKG == 70)
    #expect(legacy.weightChangeKG == 1)
    let original = legacy
    #expect(throws: DomainError.self) {
        try legacy.setProfile(heightCM: 0, weightKG: 50, targetWeightKG: 45, goalSteps: 6_000)
    }
    #expect(legacy == original)
    try legacy.setProfile(heightCM: 172, weightKG: 68, targetWeightKG: 64, goalSteps: 8_000)
    #expect(legacy.weightChangeKG == -2)
}

@Test func modularWardrobeChargesOnceAndReplacesOnlyTheMatchingSlot() throws {
    var state = try fundedFeatureState()
    try state.buyOutfit(.student)
    try state.buyItem(.shorts)
    try state.buyItem(.skirt)
    try state.buyItem(.bow)
    #expect(state.points == 200)
    #expect(state.equippedOutfit == .student)
    #expect(state.equippedItems.contains(.skirt))
    #expect(!state.equippedItems.contains(.shorts))
    #expect(state.equippedItems.contains(.bow))
    try state.equipItem(.shorts)
    #expect(state.equippedItems.contains(.shorts))
    #expect(!state.equippedItems.contains(.skirt))
    #expect(state.equippedItems.contains(.bow))
    let original = state
    #expect(throws: DomainError.self) { try state.buyItem(.shorts) }
    #expect(throws: DomainError.self) { try state.buyItem(.boots) }
    #expect(throws: DomainError.self) { try state.equipItem(.glasses) }
    #expect(state == original)
    state.unequipItem(in: .bottom)
    #expect(!state.equippedItems.contains { $0.category == .bottom })
    #expect(state.equippedItems.contains(.bow))
    #expect(state.equippedOutfit == .student)
    try state.validate()
}

@Test func corruptedModularOwnershipAndSlotCollisionsAreRejected() throws {
    var state = try fundedFeatureState()
    try state.buyItem(.shorts)
    try state.buyItem(.skirt)
    let original = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
    for equipped in [["boots"], ["shorts", "skirt"], ["shorts", "shorts"]] {
        var json = original
        json["equippedItems"] = equipped
        let data = try JSONSerialization.data(withJSONObject: json)
        #expect(throws: DomainError.self) {
            let decoded = try JSONDecoder().decode(UsagiState.self, from: data)
            try decoded.validate()
        }
    }
}

@Test func workoutCompletionRetryKeepsOneRecordAndCannotFinishANewerSession() throws {
    var state = try featureState()
    let session = try state.startWorkout(mode: .indoor, now: featureDay)
    let record = try state.finishWorkout(durationMinutes: 15, repetitions: 30, distanceMeters: nil, calories: nil,
                                        now: featureDay.addingTimeInterval(900), sessionID: session.id)
    #expect(record.id == session.id)
    #expect(record.repetitions == 30)
    #expect(record.calories == nil)
    #expect(record.distanceMeters == nil)
    #expect(state.activeWorkout == nil)
    #expect(state.workouts.count == 1)
    #expect(state.points == 0 && state.daily.steps == 0)
    let newer = try state.startWorkout(mode: .outdoor, now: featureDay.addingTimeInterval(1_000))
    let retry = try state.finishWorkout(durationMinutes: 99, repetitions: nil, distanceMeters: 9_999, calories: 99,
                                       now: featureDay.addingTimeInterval(1_100), sessionID: session.id)
    #expect(retry == record)
    #expect(state.activeWorkout?.id == newer.id)
    #expect(state.workouts == [record])
    let original = state
    #expect(throws: DomainError.self) {
        try state.finishWorkout(durationMinutes: 1, now: featureDay.addingTimeInterval(1_100), sessionID: UUID())
    }
    #expect(state == original)
}

@Test func invalidWorkoutInputsKeepTheActiveSessionAndHistory() throws {
    var unconfigured = UsagiState(now: featureDay)
    #expect(throws: DomainError.self) { try unconfigured.startWorkout(mode: .indoor, now: featureDay) }
    var state = try featureState()
    let session = try state.startWorkout(mode: .outdoor, now: featureDay)
    let original = state
    #expect(throws: DomainError.self) { try state.startWorkout(mode: .indoor, now: featureDay) }
    #expect(throws: DomainError.self) { try state.finishWorkout(durationMinutes: -1, now: featureDay.addingTimeInterval(60)) }
    #expect(throws: DomainError.self) { try state.finishWorkout(durationMinutes: 1_441, now: featureDay.addingTimeInterval(60)) }
    #expect(throws: DomainError.self) { try state.finishWorkout(durationMinutes: 1, now: featureDay.addingTimeInterval(-1)) }
    #expect(throws: DomainError.self) { try state.finishWorkout(durationMinutes: 1, repetitions: -1, now: featureDay.addingTimeInterval(60)) }
    #expect(throws: DomainError.self) { try state.finishWorkout(durationMinutes: 1, distanceMeters: .nan, now: featureDay.addingTimeInterval(60)) }
    #expect(throws: DomainError.self) { try state.finishWorkout(durationMinutes: 1, calories: -1, now: featureDay.addingTimeInterval(60)) }
    #expect(state == original)
    #expect(state.activeWorkout?.id == session.id)
    state.cancelWorkout()
    #expect(state.activeWorkout == nil)
    #expect(state.workouts.isEmpty)
    #expect(state.points == 0)
}

@Test func workoutHistoryIsBoundedAndSurvivesDayRollover() throws {
    var state = try featureState()
    var firstID: UUID?
    var lastID: UUID?
    for index in 0..<201 {
        let start = featureDay.addingTimeInterval(Double(index) * 120)
        let session = try state.startWorkout(mode: .indoor, now: start)
        if firstID == nil { firstID = session.id }
        lastID = session.id
        try state.finishWorkout(durationMinutes: 1, now: start.addingTimeInterval(60), sessionID: session.id)
    }
    #expect(state.workouts.count == 200)
    #expect(!state.workouts.contains { $0.id == firstID })
    #expect(state.workouts.contains { $0.id == lastID })
    let records = state.workouts
    state.rollover(now: featureDay.addingTimeInterval(86_400), calendar: featureCalendar)
    #expect(state.workouts == records)
    #expect(state.points == 0 && state.daily.steps == 0)
    try state.validate()
}

@Test func forgottenWorkoutCanRecordCorrectedDurationWithoutChangingItsDates() throws {
    var state = try featureState()
    let session = try state.startWorkout(mode: .indoor, now: featureDay)
    let completedAt = featureDay.addingTimeInterval(3 * 86_400)
    let original = state
    #expect(throws: DomainError.self) {
        try state.finishWorkout(durationMinutes: 30, now: featureDay.addingTimeInterval(-1), sessionID: session.id)
    }
    #expect(throws: DomainError.self) {
        try state.finishWorkout(durationMinutes: 1_441, now: completedAt, sessionID: session.id)
    }
    #expect(state == original)
    let record = try state.finishWorkout(durationMinutes: 30, now: completedAt, sessionID: session.id)
    #expect(record.durationMinutes == 30)
    #expect(record.startedAt == featureDay)
    #expect(record.endedAt == completedAt)
    #expect(state.activeWorkout == nil)
    #expect(state.workouts == [record])
    try state.validate()
}

@Test func activeWorkoutAndCustomizationSurviveAtomicLocalSave() async throws {
    var state = try featureState()
    var preferences = state.preferences
    preferences.character = .chiikawa
    preferences.name = "작은 친구"
    preferences.homeMetrics = [.water, .workoutMinutes]
    try state.setPreferences(preferences)
    let session = try state.startWorkout(mode: .indoor, now: featureDay)
    let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = LocalSaveStore(fileURL: directory.appending(path: "state.json"))
    try await store.save(state)
    let restored = try await store.load(now: featureDay, calendar: featureCalendar)
    #expect(restored == state)
    #expect(restored.activeWorkout?.id == session.id)
    #expect(restored.preferences.character == .chiikawa)
    #expect(restored.preferences.name == "작은 친구")
}
