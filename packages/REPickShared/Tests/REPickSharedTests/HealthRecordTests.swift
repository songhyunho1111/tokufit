import Foundation
import Testing
@testable import REPickShared

private let healthNow = Date(timeIntervalSince1970: 1_792_800_000)
private var healthCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar
}

private func healthState(now: Date = healthNow) throws -> UsagiState {
    var state = UsagiState(now: now, calendar: healthCalendar)
    try state.setProfile(heightCM: 170, weightKG: 70, targetWeightKG: 65, goalSteps: 6_000)
    return state
}

private func healthEncode<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(value)
}

private func healthDecode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(type, from: data)
}

private func healthObject(_ state: UsagiState) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: healthEncode(state)) as? [String: Any])
}

@Test func legacyHealthMigrationKeepsOnlyExistingMealsAndProgress() throws {
    var state = try healthState()
    try state.recordSteps(6_000)
    try state.claimReward()
    try state.buyItem(.bow)
    try state.addWater(500)
    try state.addMeal(name: "기존 식사", calories: 400, source: .manual, now: healthNow)
    var json = try healthObject(state)
    json.removeValue(forKey: "mealHistory")
    json.removeValue(forKey: "wellnessHistory")
    var restored = try healthDecode(UsagiState.self, from: JSONSerialization.data(withJSONObject: json))
    try restored.validate()
    #expect(restored.mealHistory == state.daily.meals)
    #expect(restored.mealHistory.count == 1)
    #expect(restored.mealHistory[0].nutrients == nil)
    #expect(restored.wellnessHistory.isEmpty)
    #expect(restored.points == state.points)
    #expect(restored.equippedItems == [.bow])
    restored.rollover(now: healthNow.addingTimeInterval(86_400), calendar: healthCalendar)
    #expect(restored.daily.meals.isEmpty)
    #expect(restored.mealHistory == state.daily.meals)
    #expect(restored.totalFoodCalories == 400)
    #expect(restored.points == state.points)
}

@Test func nutrientValuesRoundTripAndInvalidValuesDoNotEnterMeals() throws {
    let nutrients = try MealNutrients(carbohydratesG: 30.5, proteinG: 12, fatG: 8.25)
    var state = try healthState()
    try state.addMeal(name: "식사", calories: 300, source: .manual, now: healthNow, nutrients: nutrients)
    let restored = try healthDecode(UsagiState.self, from: healthEncode(state))
    try restored.validate()
    #expect(restored == state)
    #expect(restored.daily.meals.first?.nutrients == nutrients)
    #expect(restored.mealHistory.first?.nutrients == nutrients)
    for invalid in [-1.0, 2_000.01, .infinity, .nan] {
        #expect(throws: DomainError.self) { try MealNutrients(carbohydratesG: invalid, proteinG: 1, fatG: 1) }
        #expect(throws: DomainError.self) { try MealNutrients(carbohydratesG: 1, proteinG: invalid, fatG: 1) }
        #expect(throws: DomainError.self) { try MealNutrients(carbohydratesG: 1, proteinG: 1, fatG: invalid) }
    }
    #expect(try MealNutrients(carbohydratesG: 0, proteinG: 0, fatG: 0).carbohydratesG == 0)
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(MealNutrients.self, from: Data(#"{"carbohydratesG":20,"proteinG":5}"#.utf8))
    }
    let before = state
    #expect(throws: DomainError.self) {
        try state.addMeal(name: "", calories: 300, source: .manual, now: healthNow, nutrients: nutrients)
    }
    #expect(state == before)
}

@Test func wellnessKeepsKnownZeroAndReplacesOneCalendarDay() throws {
    var state = try healthState()
    let day = UsagiState.dayKey(for: healthNow, calendar: healthCalendar)
    try state.recordWellness(day: day, sleepMinutes: 0, now: healthNow, calendar: healthCalendar)
    #expect(state.wellnessHistory.count == 1)
    #expect(state.wellnessHistory[0].sleepMinutes == 0)
    #expect(state.wellnessHistory[0].condition == nil)
    try state.recordWellness(day: day, sleepMinutes: 420, condition: 4, now: healthNow, calendar: healthCalendar)
    #expect(state.wellnessHistory.count == 1)
    #expect(state.wellnessHistory[0].sleepMinutes == 420)
    #expect(state.wellnessHistory[0].condition == 4)
    #expect(try healthDecode(UsagiState.self, from: healthEncode(state)) == state)
}

@Test func wellnessRejectsInvalidDatesAndValuesWithoutChangingState() throws {
    var state = try healthState()
    let day = UsagiState.dayKey(for: healthNow, calendar: healthCalendar)
    let before = state
    for invalidDay in ["2026-02-30", "2026-2-03",
                       UsagiState.dayKey(for: healthNow.addingTimeInterval(86_400), calendar: healthCalendar),
                       UsagiState.dayKey(for: healthNow.addingTimeInterval(-366 * 86_400), calendar: healthCalendar)] {
        #expect(throws: DomainError.self) {
            try state.recordWellness(day: invalidDay, sleepMinutes: 420, now: healthNow, calendar: healthCalendar)
        }
    }
    for minutes in [-1, 1_441] {
        #expect(throws: DomainError.self) {
            try state.recordWellness(day: day, sleepMinutes: minutes, now: healthNow, calendar: healthCalendar)
        }
    }
    for condition in [0, 6] {
        #expect(throws: DomainError.self) {
            try state.recordWellness(day: day, condition: condition, now: healthNow, calendar: healthCalendar)
        }
    }
    #expect(throws: DomainError.self) {
        try state.recordWellness(day: day, now: healthNow, calendar: healthCalendar)
    }
    #expect(state == before)
}

@Test func historyRetentionPreservesRecentRecordsAndPrunesExpiredOnes() throws {
    let expired = healthNow.addingTimeInterval(-366 * 86_400)
    let boundary = healthNow.addingTimeInterval(-365 * 86_400)
    var state = try healthState(now: expired)
    try state.addMeal(name: "오래된 기록", calories: 100, source: .manual, now: expired)
    try state.recordWellness(day: UsagiState.dayKey(for: expired, calendar: healthCalendar), sleepMinutes: 420,
                             now: expired, calendar: healthCalendar)
    state.rollover(now: boundary, calendar: healthCalendar)
    try state.addMeal(name: "유지할 기록", calories: 200, source: .manual, now: boundary)
    try state.recordWellness(day: UsagiState.dayKey(for: boundary, calendar: healthCalendar), condition: 3,
                             now: boundary, calendar: healthCalendar)
    state.rollover(now: healthNow, calendar: healthCalendar)
    #expect(state.mealHistory.map(\.name) == ["유지할 기록"])
    #expect(state.wellnessHistory.count == 1)
    #expect(state.wellnessHistory[0].day == UsagiState.dayKey(for: boundary, calendar: healthCalendar))
    #expect(state.totalFoodCalories == 300)
    state.rollover(now: healthNow.addingTimeInterval(30), calendar: healthCalendar)
    #expect(state.mealHistory.count == 1)
    try state.validate()
}

@Test func historyCapKeepsNewestMealsWithoutErasingDailyDisplay() throws {
    var state = try healthState()
    let entries = try (0..<5_000).map { index in
        try MealEntry(name: "기록 \(index)", calories: 1, source: .manual,
                      recordedAt: healthNow.addingTimeInterval(Double(index - 6_000)))
    }
    var json = try healthObject(state)
    json["mealHistory"] = try JSONSerialization.jsonObject(with: healthEncode(entries))
    json["totalFoodCalories"] = 5_000
    state = try healthDecode(UsagiState.self, from: JSONSerialization.data(withJSONObject: json))
    try state.validate()
    try state.addMeal(name: "최근 기록", calories: 10, source: .manual, now: healthNow)
    #expect(state.mealHistory.count == 5_000)
    #expect(state.mealHistory.last?.name == "최근 기록")
    #expect(!state.mealHistory.contains { $0.id == entries[0].id })
    #expect(state.daily.meals.last?.name == "최근 기록")
    try state.validate()
}

@Test func healthHistoryRejectsNullDuplicatesAndConflictingMealIdentity() throws {
    var state = try healthState()
    try state.addMeal(name: "현재 기록", calories: 300, source: .manual, now: healthNow)
    let original = try healthObject(state)
    for field in ["mealHistory", "wellnessHistory"] {
        var json = original
        json[field] = NSNull()
        #expect(throws: DecodingError.self) {
            try healthDecode(UsagiState.self, from: JSONSerialization.data(withJSONObject: json))
        }
    }
    var json = original
    let history = try #require(json["mealHistory"] as? [[String: Any]])
    json["mealHistory"] = history + history
    let duplicate = try healthDecode(UsagiState.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(throws: DomainError.self) { try duplicate.validate() }
    var changed = history[0]
    changed["calories"] = 200
    json["mealHistory"] = [changed]
    let conflict = try healthDecode(UsagiState.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(throws: DomainError.self) { try conflict.validate() }
    json = original
    let entry = try WellnessEntry(day: UsagiState.dayKey(for: healthNow, calendar: healthCalendar), condition: 3)
    json["wellnessHistory"] = try JSONSerialization.jsonObject(with: healthEncode([entry, entry]))
    let duplicateDay = try healthDecode(UsagiState.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(throws: DomainError.self) { try duplicateDay.validate() }
}

@Test func compactWatchSnapshotKeepsTodayButOmitsHealthHistoryAcrossEncoding() throws {
    var state = try healthState()
    try state.addMeal(name: "식사", calories: 300, source: .manual, now: healthNow)
    try state.recordWellness(day: UsagiState.dayKey(for: healthNow, calendar: healthCalendar), condition: 3,
                             now: healthNow, calendar: healthCalendar)
    let original = state
    let snapshot = state.watchSnapshot()
    let decoded = try healthDecode(UsagiState.self, from: healthEncode(snapshot))
    #expect(decoded.daily == state.daily)
    #expect(decoded.mealHistory.isEmpty && decoded.wellnessHistory.isEmpty && decoded.workouts.isEmpty)
    #expect(state == original)
    try decoded.validate()
}

@Test func optionalWorkoutActivityDoesNotInventLegacyExerciseKinds() throws {
    var state = try healthState()
    let first = try state.startWorkout(mode: .outdoor, now: healthNow)
    let unspecified = try state.finishWorkout(durationMinutes: 10, now: healthNow.addingTimeInterval(600), sessionID: first.id)
    #expect(unspecified.activity == nil)
    let second = try state.startWorkout(mode: .indoor, now: healthNow.addingTimeInterval(700))
    let strength = try state.finishWorkout(durationMinutes: 20, repetitions: 30, now: healthNow.addingTimeInterval(1_900),
                                          sessionID: second.id, activity: .strength)
    #expect(strength.activity == .strength)
    #expect(try healthDecode(UsagiState.self, from: healthEncode(state)) == state)
}

@Test func corruptHealthHistoryIsPreservedOnDisk() async throws {
    var state = try healthState()
    try state.addMeal(name: "식사", calories: 300, source: .manual, now: healthNow)
    var json = try healthObject(state)
    var history = try #require(json["mealHistory"] as? [[String: Any]])
    history[0]["nutrients"] = ["carbohydratesG": 2_001, "proteinG": 5, "fatG": 3]
    json["mealHistory"] = history
    let data = try JSONSerialization.data(withJSONObject: json)
    let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appending(path: "state.json")
    try data.write(to: file)
    let store = LocalSaveStore(fileURL: file)
    await #expect(throws: DomainError.self) { try await store.load(now: healthNow, calendar: healthCalendar) }
    #expect(try Data(contentsOf: file) == data)
}
