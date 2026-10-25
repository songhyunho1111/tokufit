import Foundation
import Testing
@testable import REPickShared

private var growthCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar
}

private func growthDate(_ text: String = "2026-10-01T12:00:00Z") throws -> Date {
    try #require(ISO8601DateFormatter().date(from: text))
}

private func growthState(now: Date? = nil) throws -> UsagiState {
    var state = UsagiState(now: try now ?? growthDate(), calendar: growthCalendar)
    try state.setProfile(heightCM: 170, weightKG: 70, targetWeightKG: 65, goalSteps: 2_000)
    return state
}

private func attendanceState(days: Int, stepsFirst: Bool = false) throws -> UsagiState {
    var state = try growthState()
    let start = try growthDate()
    for index in 0..<days {
        let now = start.addingTimeInterval(Double(index) * 86_400)
        state.rollover(now: now, calendar: growthCalendar)
        if stepsFirst { try state.recordSteps(2_000) }
        try state.checkIn(now: now, calendar: growthCalendar)
        if !stepsFirst { try state.recordSteps(2_000) }
    }
    return state
}

private func growthJSON(_ state: UsagiState) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
}

private func decodeGrowth(_ json: [String: Any]) throws -> UsagiState {
    let state = try JSONDecoder().decode(UsagiState.self, from: JSONSerialization.data(withJSONObject: json))
    try state.validate()
    return state
}

@Test(arguments: [false, true])
func attendanceGrantsEachTenthConsecutiveDayExactlyOnceInEitherEventOrder(stepsFirst: Bool) throws {
    var state = try attendanceState(days: 40, stepsFirst: stepsFirst)
    #expect(state.attendanceStreak == 40)
    #expect(state.freeDraws == 4)
    #expect(state.points == 0)
    #expect(state.daily.draws == 0)
    #expect(state.attendance.days.count == 40)
    #expect(state.attendance.lastRewardDay == state.daily.day)
    let before = state
    try state.checkIn(now: growthDate().addingTimeInterval(39 * 86_400), calendar: growthCalendar)
    try state.recordSteps(2_001)
    #expect(state.freeDraws == before.freeDraws)
    try state.validate()
}

@Test func incompleteMilestoneDoesNotGrantOnTheFollowingDay() throws {
    var state = try attendanceState(days: 9)
    let milestone = try growthDate().addingTimeInterval(9 * 86_400)
    try state.checkIn(now: milestone, calendar: growthCalendar)
    #expect(state.attendanceStreak == 10 && state.freeDraws == 0)
    let tomorrow = milestone.addingTimeInterval(86_400)
    try state.checkIn(now: tomorrow, calendar: growthCalendar)
    try state.recordSteps(2_000)
    #expect(state.attendanceStreak == 11 && state.freeDraws == 0)
    #expect(state.attendance.lastRewardDay == nil)
}

@Test func milestoneUsesTheGoalAlreadyScheduledForThatCalendarDay() throws {
    var state = try attendanceState(days: 9)
    try state.setNextGoal(8_000)
    let milestone = try growthDate().addingTimeInterval(9 * 86_400)
    try state.checkIn(now: milestone, calendar: growthCalendar)
    try state.recordSteps(2_000)
    #expect(state.freeDraws == 0 && state.daily.goalSteps == 8_000)
    try state.setNextGoal(2_000)
    try state.recordSteps(8_000)
    #expect(state.freeDraws == 1 && state.daily.goalSteps == 8_000)
}

@Test func attentionStartsOnlyAfterAFullMissedDayAndClearsOnCheckIn() throws {
    var state = try growthState()
    let start = try growthDate()
    state.rollover(now: start.addingTimeInterval(20 * 86_400), calendar: growthCalendar)
    #expect(!state.attendanceNeedsAttention && state.attendanceStreak == 0)
    try state.checkIn(now: start.addingTimeInterval(20 * 86_400), calendar: growthCalendar)
    state.rollover(now: start.addingTimeInterval(21 * 86_400), calendar: growthCalendar)
    #expect(!state.hasCheckedInToday && !state.attendanceNeedsAttention && state.attendanceStreak == 1)
    state.rollover(now: start.addingTimeInterval(22 * 86_400), calendar: growthCalendar)
    #expect(state.attendanceNeedsAttention && state.attendanceStreak == 0)
    try state.checkIn(now: start.addingTimeInterval(22 * 86_400), calendar: growthCalendar)
    #expect(state.hasCheckedInToday && !state.attendanceNeedsAttention && state.attendanceStreak == 1)
    #expect(state.attendance.days.count == 2)
}

@Test func attendanceHonorsLeapDaysDSTAndGregorianKeys() throws {
    let leap = try growthDate("2028-02-28T12:00:00Z")
    var state = try growthState(now: leap)
    for index in 0..<3 {
        try state.checkIn(now: leap.addingTimeInterval(Double(index) * 86_400), calendar: growthCalendar)
    }
    #expect(state.attendance.days == ["2028-02-28", "2028-02-29", "2028-03-01"])
    #expect(state.attendanceStreak == 3)

    var losAngeles = growthCalendar
    losAngeles.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
    let beforeDST = try growthDate("2026-03-07T20:00:00Z")
    let afterDST = try growthDate("2026-03-08T19:00:00Z")
    var dst = UsagiState(now: beforeDST, calendar: losAngeles)
    try dst.setProfile(heightCM: 170, weightKG: 70, targetWeightKG: 65, goalSteps: 2_000)
    try dst.checkIn(now: beforeDST, calendar: losAngeles)
    try dst.checkIn(now: afterDST, calendar: losAngeles)
    #expect(dst.attendanceStreak == 2)
    var buddhist = Calendar(identifier: .buddhist)
    buddhist.timeZone = losAngeles.timeZone
    try dst.checkIn(now: afterDST, calendar: buddhist)
    #expect(dst.attendance.days == ["2026-03-07", "2026-03-08"])
}

@Test func backwardClockAndTimezoneCannotReopenAttendanceRewards() throws {
    var state = try attendanceState(days: 10)
    let before = state
    let yesterday = try growthDate().addingTimeInterval(8 * 86_400)
    #expect(throws: GrowthError.clockMovedBackward) { try state.checkIn(now: yesterday, calendar: growthCalendar) }
    state.rollover(now: yesterday, calendar: growthCalendar)
    #expect(state == before)
    var west = growthCalendar
    west.timeZone = try #require(TimeZone(secondsFromGMT: -12 * 3_600))
    let midnightUTC = try growthDate("2026-10-10T00:30:00Z")
    #expect(throws: GrowthError.clockMovedBackward) { try state.checkIn(now: midnightUTC, calendar: west) }
    #expect(state == before)
}

@Test func attendanceHistoryIsBoundedWithoutResettingLongStreakOrTickets() throws {
    let state = try attendanceState(days: 401)
    #expect(state.attendance.days.count == 366)
    #expect(state.attendanceStreak == 401)
    #expect(state.freeDraws == 40)
    try state.validate()
}

@Test func freeCostumeDrawCarriesAcrossDaysAndDoesNotUsePaidQuota() throws {
    var state = try attendanceState(days: 10)
    state.rollover(now: try growthDate().addingTimeInterval(12 * 86_400), calendar: growthCalendar)
    #expect(state.freeDraws == 1 && !state.daily.isGoalComplete)
    let receipt = try state.openGacha(id: UUID(), randomIndex: 0, payment: .free)
    #expect(receipt.payment == .free && receipt.costume == CharacterCostume(character: .usagi, style: .mermaidIsland) && !receipt.wasDuplicate)
    #expect(state.freeDraws == 0 && state.daily.draws == 0 && state.points == 0)
    #expect(state.currentCostume == .mermaidIsland && state.equippedOutfit == .basic)
    try state.validate()
}

@Test func gachaDuplicateRefundAndReceiptAreIdempotentAcrossRelaunch() throws {
    var state = try attendanceState(days: 20)
    _ = try state.openGacha(id: UUID(), randomIndex: 0, payment: .free)
    let id = UUID()
    let duplicate = try state.openGacha(id: id, randomIndex: 0, payment: .free)
    #expect(duplicate.wasDuplicate && state.points == 50 && state.freeDraws == 0)
    state = try decodeGrowth(growthJSON(state))
    let before = state
    let retry = try state.openGacha(id: id, randomIndex: 2, payment: .points)
    #expect(retry == duplicate && state == before)
}

@Test func capturedGachaPaymentNeverSwitchesAndPaidRulesRemainIntact() throws {
    var state = try attendanceState(days: 10)
    try state.claimReward()
    _ = try state.openGacha(id: UUID(), randomIndex: 0, payment: .points)
    #expect(state.freeDraws == 1 && state.daily.draws == 1 && state.points == 0)
    let capped = state
    #expect(throws: DomainError.dailyDrawLimit) { try state.openGacha(id: UUID(), randomIndex: 1, payment: .points) }
    #expect(state == capped)
    _ = try state.openGacha(id: UUID(), randomIndex: 1, payment: .free)
    let spent = state
    #expect(throws: GrowthError.noFreeDraws) { try state.openGacha(id: UUID(), randomIndex: 2, payment: .free) }
    #expect(state == spent)
    #expect(state.daily.draws == 1)
    state.rollover(now: try growthDate().addingTimeInterval(10 * 86_400), calendar: growthCalendar)
    try state.recordSteps(2_000)
    try state.claimReward()
    let funded = state
    #expect(state.points == 100)
    #expect(throws: GrowthError.noFreeDraws) { try state.openGacha(id: UUID(), randomIndex: 2, payment: .free) }
    #expect(state == funded)
}

@Test func gachaReceiptRetentionIsBoundedAndRecentRetryDoesNotSpendAgain() throws {
    var json = try growthJSON(growthState())
    json["freeDraws"] = 201
    var state = try decodeGrowth(json)
    var firstID: UUID?
    var last: GachaReceipt?
    for _ in 0..<201 {
        let id = UUID()
        if firstID == nil { firstID = id }
        last = try state.openGacha(id: id, randomIndex: 0, payment: .free)
    }
    #expect(state.gachaReceipts.count == 200 && state.freeDraws == 0)
    #expect(!state.gachaReceipts.contains { $0.id == firstID })
    let before = state
    let receipt = try #require(last)
    #expect(try state.openGacha(id: receipt.id, randomIndex: 1, payment: .points) == receipt)
    #expect(state == before)
    try state.validate()
}

@Test func gachaValidationAndOverflowDoNotConsumeAnOpportunity() throws {
    var state = try attendanceState(days: 20)
    let original = state
    #expect(throws: DomainError.invalidOutfit) { try state.openGacha(id: UUID(), randomIndex: -1, payment: .free) }
    #expect(throws: DomainError.invalidOutfit) { try state.openGacha(id: UUID(), randomIndex: 3, payment: .free) }
    #expect(state == original)
    _ = try state.openGacha(id: UUID(), randomIndex: 0, payment: .free)
    var json = try growthJSON(state)
    json["points"] = Int.max
    state = try decodeGrowth(json)
    let overflowState = state
    #expect(throws: DomainError.invalidSave) { try state.openGacha(id: UUID(), randomIndex: 0, payment: .free) }
    #expect(state == overflowState)
}

@Test func attendanceAwardOverflowKeepsStepsAndCheckInAtomic() throws {
    var state = try attendanceState(days: 9)
    try state.checkIn(now: growthDate().addingTimeInterval(9 * 86_400), calendar: growthCalendar)
    var json = try growthJSON(state)
    json["freeDraws"] = Int.max
    state = try decodeGrowth(json)
    let before = state
    #expect(throws: DomainError.invalidSave) { try state.recordSteps(2_000) }
    #expect(state == before)
}

@Test func exerciseEstimateUsesConservativeActiveEnergyAndUnknownStaysUnknown() {
    #expect(ExerciseEnergy.estimateCalories(activity: .walking, minutes: 30, weightKG: 70) == 63)
    #expect(ExerciseEnergy.estimateCalories(activity: .running, minutes: 30, weightKG: 70) == 192)
    #expect(ExerciseEnergy.estimateCalories(activity: .cycling, minutes: 30, weightKG: 70) == 87)
    #expect(ExerciseEnergy.estimateCalories(activity: .strength, minutes: 30, weightKG: 70) == 70)
    #expect(ExerciseEnergy.estimateCalories(activity: .stretching, minutes: 30, weightKG: 70) == 45)
    #expect(ExerciseEnergy.estimateCalories(activity: .other, minutes: 30, weightKG: 70) == nil)
    for minutes in [0, -1, 1_441, Int.max] {
        #expect(ExerciseEnergy.estimateCalories(activity: .walking, minutes: minutes, weightKG: 70) == nil)
    }
    for weight in [Double.nan, .infinity, 19, 351] {
        #expect(ExerciseEnergy.estimateCalories(activity: .walking, minutes: 30, weightKG: weight) == nil)
    }
    #expect(ExerciseEnergy.estimateCalories(activity: .running, minutes: 1_440, weightKG: 350) == nil)
}

@Test func workoutUsesSessionActivityManualOverrideAndCreditsOnlyOnce() throws {
    let start = try growthDate()
    var state = try growthState()
    let session = try state.startWorkout(mode: .indoor, now: start, activity: .strength)
    state = try decodeGrowth(growthJSON(state))
    #expect(state.activeWorkout?.activity == .strength)
    let record = try state.finishWorkout(durationMinutes: 30, repetitions: 12, now: start.addingTimeInterval(1_800), sessionID: session.id, calendar: growthCalendar)
    #expect(record.activity == .strength && record.calories == 70 && record.calorieSource == .estimated)
    #expect(record.durationMinutes == 30 && record.repetitions == 12)
    #expect(state.totalExerciseCalories == 70 && state.exerciseCaloriesToday == 70)
    #expect(state.totalStrengthMinutes == 30 && state.muscleLevel == 0.1)
    let next = try state.startWorkout(mode: .indoor, now: start.addingTimeInterval(2_000), activity: .strength)
    let before = state
    #expect(try state.finishWorkout(durationMinutes: 99, calories: 9_999, sessionID: session.id) == record)
    #expect(state == before)
    let manual = try state.finishWorkout(durationMinutes: 10, calories: 0, now: start.addingTimeInterval(2_600), sessionID: next.id, activity: .walking, calendar: growthCalendar)
    #expect(manual.calories == 0 && manual.calorieSource == .manual && manual.activity == .walking)
    #expect(state.totalExerciseCalories == 70 && state.totalStrengthMinutes == 30)
    try state.validate()
}

@Test func explicitOtherAndLegacyUnknownWorkoutsDoNotInventEnergy() throws {
    var state = try growthState()
    let start = try growthDate()
    let first = try state.startWorkout(mode: .indoor, now: start, activity: .strength)
    let unknown = try state.finishWorkout(durationMinutes: 30, now: start.addingTimeInterval(1_800), sessionID: first.id, activity: .other)
    #expect(unknown.activity == .other && unknown.calories == nil && unknown.calorieSource == nil)
    let second = try state.startWorkout(mode: .outdoor, now: start.addingTimeInterval(2_000))
    let legacy = try state.finishWorkout(durationMinutes: 30, now: start.addingTimeInterval(3_800), sessionID: second.id)
    #expect(legacy.activity == nil && legacy.calories == nil && legacy.calorieSource == nil)
    #expect(state.totalExerciseCalories == 0 && state.totalStrengthMinutes == 0)
}

@Test func workoutEnergyUsesCompletionDayAndOverflowKeepsActiveSession() throws {
    let start = try growthDate("2026-10-01T14:30:00Z")
    var seoul = growthCalendar
    seoul.timeZone = try #require(TimeZone(identifier: "Asia/Seoul"))
    var state = try growthState(now: start)
    let session = try state.startWorkout(mode: .indoor, now: start, activity: .strength)
    let nextDay = try growthDate("2026-10-01T15:01:00Z")
    state.rollover(now: nextDay, calendar: seoul)
    try state.finishWorkout(durationMinutes: 20, calories: 50, now: start.addingTimeInterval(1_200), sessionID: session.id, calendar: seoul)
    #expect(state.totalExerciseCalories == 50 && state.exerciseCaloriesToday == 0)
    #expect(state.daily.day == "2026-10-02")
    let next = try state.startWorkout(mode: .indoor, now: nextDay, activity: .strength)
    var json = try growthJSON(state)
    json["totalExerciseCalories"] = Int.max
    state = try decodeGrowth(json)
    let before = state
    #expect(throws: DomainError.invalidSave) {
        try state.finishWorkout(durationMinutes: 1, calories: 1, now: nextDay.addingTimeInterval(60), sessionID: next.id, calendar: seoul)
    }
    #expect(state == before)
}

@Test func cumulativeGrowthSurvivesRetentionWithoutChangingFoodAppearanceWeightOrGrossFood() throws {
    var state = try growthState()
    let start = try growthDate()
    try state.addMeal(name: "Meal", calories: 500, source: .manual, now: start)
    let profile = state.profile
    let meal = state.daily.meals
    let scale = state.bodyScale
    var firstID: UUID?
    for index in 0..<301 {
        let now = start.addingTimeInterval(Double(index) * 120)
        let session = try state.startWorkout(mode: .indoor, now: now, activity: .strength)
        if firstID == nil { firstID = session.id }
        try state.finishWorkout(durationMinutes: 1, calories: 100, now: now.addingTimeInterval(60), sessionID: session.id, calendar: growthCalendar)
    }
    #expect(state.workouts.count == 200)
    #expect(state.totalExerciseCalories == 30_100 && state.exerciseCaloriesToday == 30_100)
    #expect(state.totalStrengthMinutes == 301 && state.muscleLevel == 1)
    #expect(state.profile == profile && state.totalFoodCalories == 500 && state.daily.meals == meal)
    #expect(state.bodyScale == scale && state.bodyScale == 1)
    let before = state
    #expect(throws: DomainError.noActiveWorkout) { try state.finishWorkout(durationMinutes: 1, calories: 100, sessionID: firstID) }
    #expect(state == before)
    state.rollover(now: start.addingTimeInterval(86_400), calendar: growthCalendar)
    #expect(state.exerciseCaloriesToday == 0 && state.totalExerciseCalories == 30_100)
    #expect(state.totalStrengthMinutes == 301)
    try state.validate()
}

@Test func legacyGrowthMigrationKeepsKnownValuesWithoutRetroactiveAttendanceOrEstimates() throws {
    var state = try growthState()
    let start = try growthDate()
    let session = try state.startWorkout(mode: .indoor, now: start, activity: .strength)
    try state.finishWorkout(durationMinutes: 30, calories: 80, now: start.addingTimeInterval(1_800), sessionID: session.id)
    var json = try growthJSON(state)
    for key in ["attendance", "freeDraws", "gachaReceipts", "exerciseCaloriesToday", "totalExerciseCalories", "totalStrengthMinutes"] {
        json.removeValue(forKey: key)
    }
    var records = try #require(json["workouts"] as? [[String: Any]])
    records[0].removeValue(forKey: "calorieSource")
    json["workouts"] = records
    let migrated = try decodeGrowth(json)
    #expect(migrated.totalExerciseCalories == 80 && migrated.totalStrengthMinutes == 30)
    #expect(migrated.workouts[0].calorieSource == nil)
    #expect(migrated.attendance == AttendanceProgress() && migrated.freeDraws == 0)
    records[0].removeValue(forKey: "calories")
    json["workouts"] = records
    let unknown = try decodeGrowth(json)
    #expect(unknown.totalExerciseCalories == 0 && unknown.workouts[0].calories == nil)
    #expect(unknown.totalStrengthMinutes == 30)
}

@Test(arguments: ["attendance", "freeDraws", "gachaReceipts", "exerciseCaloriesToday", "totalExerciseCalories", "totalStrengthMinutes"])
func growthSaveRejectsNullNewNonoptionalFields(key: String) throws {
    var json = try growthJSON(growthState())
    json[key] = NSNull()
    #expect(throws: (any Error).self) { try decodeGrowth(json) }
}

@Test func growthSaveRejectsInvalidCountersDatesAndReceiptOwnership() throws {
    let original = try growthJSON(attendanceState(days: 10))
    for key in ["freeDraws", "exerciseCaloriesToday", "totalExerciseCalories", "totalStrengthMinutes"] {
        var json = original
        json[key] = -1
        #expect(throws: DomainError.invalidSave) { try decodeGrowth(json) }
    }
    var json = original
    var attendance = try #require(json["attendance"] as? [String: Any])
    attendance["lastCheckInDay"] = "2026-02-30"
    json["attendance"] = attendance
    #expect(throws: DomainError.invalidSave) { try decodeGrowth(json) }
    json = original
    json["gachaReceipts"] = [["id": UUID().uuidString, "outfit": "office", "wasDuplicate": false, "payment": "free"]]
    #expect(throws: DomainError.invalidSave) { try decodeGrowth(json) }
}

@Test func watchGrowthProjectionPreservesAppearanceWithoutSendingReceiptsOrAttendanceHistory() throws {
    var state = try attendanceState(days: 20)
    _ = try state.openGacha(id: UUID(), randomIndex: 0, payment: .free)
    let now = try growthDate().addingTimeInterval(19 * 86_400)
    let session = try state.startWorkout(mode: .indoor, now: now, activity: .strength)
    try state.finishWorkout(durationMinutes: 30, now: now.addingTimeInterval(1_800), sessionID: session.id)
    let snapshot = try decodeGrowth(growthJSON(state.watchSnapshot()))
    #expect(snapshot.attendance.days.isEmpty && snapshot.gachaReceipts.isEmpty && snapshot.workouts.isEmpty)
    #expect(snapshot.attendanceStreak == state.attendanceStreak && snapshot.attendanceNeedsAttention == state.attendanceNeedsAttention)
    #expect(snapshot.freeDraws == state.freeDraws && snapshot.muscleLevel == state.muscleLevel)
    #expect(snapshot.bodyScale == state.bodyScale && snapshot.exerciseCaloriesToday == state.exerciseCaloriesToday)
    #expect(state.attendance.days.count == 20 && state.gachaReceipts.count == 1)
}

@Test func attendanceDrawAndGrowthPersistAtomicallyWithoutOverwritingFailedSave() async throws {
    let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "state.json")
    let disk = LocalSaveStore(fileURL: url)
    var state = try attendanceState(days: 10)
    let now = try growthDate().addingTimeInterval(9 * 86_400)
    try await disk.save(state)
    var loaded = try await disk.load(now: now, calendar: growthCalendar)
    #expect(loaded == state)
    let id = UUID()
    let receipt = try loaded.openGacha(id: id, randomIndex: 0, payment: .free)
    let bytes = try Data(contentsOf: url)
    let failedDisk = LocalSaveStore(fileURL: url.appending(path: "blocked.json"))
    do {
        try await failedDisk.save(loaded)
        Issue.record("Saving inside an existing file must fail")
    } catch {}
    #expect(try Data(contentsOf: url) == bytes)
    let unchanged = try await disk.load(now: now, calendar: growthCalendar)
    #expect(unchanged == state && unchanged.freeDraws == 1)
    try await disk.save(loaded)
    state = try await disk.load(now: now, calendar: growthCalendar)
    let before = state
    #expect(try state.openGacha(id: id, randomIndex: 2, payment: .points) == receipt)
    #expect(state == before)
}
