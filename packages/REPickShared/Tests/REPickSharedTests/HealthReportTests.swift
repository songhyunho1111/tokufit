import Foundation
import Testing
@testable import REPickShared

private func reportDate(_ value: String) throws -> Date {
    try #require(APIStatus(status: "", service: "", timestamp: value).date)
}

private func reportState(at date: Date) throws -> UsagiState {
    var state = UsagiState(now: date)
    try state.setProfile(heightCM: 170, weightKG: 70, targetWeightKG: 65, goalSteps: 6_000)
    return state
}

@Test func reportWindowsUseMondayAndActualCalendarMonths() throws {
    let utc = try #require(TimeZone(identifier: "UTC"))
    let week = try HealthReportPeriod.week.window(containing: "2026-10-24", timeZone: utc,
                                                  now: reportDate("2026-10-24T08:00:00Z"))
    #expect(week.startDate == "2026-10-19")
    #expect(week.endDate == "2026-10-25")
    #expect(week.observedThroughDate == "2026-10-24")
    #expect(week.dayCount == 7 && week.elapsedDays == 6)
    let leap = try HealthReportPeriod.month.window(containing: "2024-02-21", timeZone: utc,
                                                   now: reportDate("2024-03-05T08:00:00Z"))
    #expect(leap.startDate == "2024-02-01" && leap.endDate == "2024-02-29")
    #expect(leap.dayCount == 29 && leap.elapsedDays == 29)
    let year = try HealthReportPeriod.week.window(containing: "2027-01-01", timeZone: utc,
                                                   now: reportDate("2027-01-01T08:00:00Z"))
    #expect(year.startDate == "2026-12-28" && year.endDate == "2027-01-03")
}

@Test func reportWindowsRespectLocalMidnightAndLookbackBounds() throws {
    let seoul = try #require(TimeZone(identifier: "Asia/Seoul"))
    let utc = try #require(TimeZone(identifier: "UTC"))
    let now = try reportDate("2026-10-24T15:30:00Z")
    let local = try HealthReportPeriod.week.window(containing: "2026-10-24", timeZone: seoul, now: now)
    let universal = try HealthReportPeriod.week.window(containing: "2026-10-24", timeZone: utc, now: now)
    #expect(local.observedThroughDate == "2026-10-25" && local.elapsedDays == 7)
    #expect(universal.observedThroughDate == "2026-10-24" && universal.elapsedDays == 6)
    for day in ["2026-02-30", "2026-13-01", "2026-1-01", "2026-10-25", "2025-10-22"] {
        #expect(throws: HealthReportError.self) {
            try HealthReportPeriod.week.window(containing: day, timeZone: utc, now: now)
        }
    }
    _ = try HealthReportPeriod.week.window(containing: "2025-10-23", timeZone: utc, now: now)
    let fixedOffset = try #require(TimeZone(secondsFromGMT: 5_400))
    #expect(throws: HealthReportError.self) {
        try HealthReportPeriod.week.window(containing: "2026-10-24", timeZone: fixedOffset, now: now)
    }
}

@Test func reportRequestFiltersMergesAndExcludesUnneededPersonalFields() throws {
    let old = try reportDate("2026-10-18T01:00:00Z")
    let now = try reportDate("2026-10-24T08:00:00Z")
    let zone = try #require(TimeZone(identifier: "Asia/Seoul"))
    var state = try reportState(at: old)
    try state.addMeal(name: "PRIVATE old food", calories: 400, source: .manual, now: old)
    state.rollover(now: now)
    try state.addMeal(name: "PRIVATE current food", calories: 500, source: .manual, now: now)
    try state.recordWellness(day: "2026-10-23", sleepMinutes: 0, condition: nil, now: now)
    let session = try state.startWorkout(mode: .indoor, now: now.addingTimeInterval(-1_800))
    try state.finishWorkout(durationMinutes: 30, now: now, sessionID: session.id, activity: .strength)
    let futureSession = try state.startWorkout(mode: .outdoor, now: now.addingTimeInterval(3_600))
    try state.finishWorkout(durationMinutes: 10, now: now.addingTimeInterval(4_200), sessionID: futureSession.id)
    let request = try HealthReportRequest.make(state: state, period: .week, anchorDate: "2026-10-24", timeZone: zone, now: now)
    #expect(request.hasRecords)
    #expect(request.data.meals.count == 1)
    #expect(request.data.workouts.count == 1)
    #expect(request.data.workouts.first?.activity == .strength)
    #expect(request.data.wellness.first?.sleepMinutes == 0)
    let encoded = try HealthReportCoding.encoder().encode(request)
    let text = String(decoding: encoded, as: UTF8.self)
    for forbidden in ["PRIVATE", "heightCM", "weightKG", "gender", "preferences", "\"name\"", "\"source\""] {
        #expect(!text.contains(forbidden))
    }
    let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let goals = try #require(object["goals"] as? [String: Any])
    #expect(goals["calorieMinimum"] is NSNull)
    #expect(goals["calorieMaximum"] is NSNull)
    let records = try #require(object["data"] as? [String: Any])
    let meals = try #require(records["meals"] as? [[String: Any]])
    #expect(meals.first?["nutrients"] is NSNull)
    let workouts = try #require(records["workouts"] as? [[String: Any]])
    for field in ["calories", "distanceMeters", "repetitions"] { #expect(workouts.first?[field] is NSNull) }
    let wellness = try #require(records["wellness"] as? [[String: Any]])
    #expect(wellness.first?["condition"] is NSNull)
}

@Test func reportRequestUsesSelectedTimezoneForMealDay() throws {
    let now = try reportDate("2026-10-19T03:00:00Z")
    let mealDate = try reportDate("2026-10-18T16:00:00Z")
    var state = try reportState(at: now)
    try state.addMeal(name: "Late meal", calories: 400, source: .manual, now: mealDate)
    let seoul = try #require(TimeZone(identifier: "Asia/Seoul"))
    let utc = try #require(TimeZone(identifier: "UTC"))
    #expect(try HealthReportRequest.make(state: state, period: .week, anchorDate: "2026-10-19", timeZone: seoul, now: now).data.meals.count == 1)
    #expect(try HealthReportRequest.make(state: state, period: .week, anchorDate: "2026-10-19", timeZone: utc, now: now).data.meals.isEmpty)
}

@Test func reportEmptyDataRemainsEmptyInsteadOfInventingMetrics() throws {
    let now = try reportDate("2026-10-24T08:00:00Z")
    let state = try reportState(at: now)
    let request = try HealthReportRequest.make(state: state, period: .month, anchorDate: "2026-10-24", now: now)
    #expect(!request.hasRecords)
    #expect(request.data.meals.isEmpty && request.data.workouts.isEmpty && request.data.wellness.isEmpty)
}

private func reportStateWithMeals(_ count: Int, nutrients: [String: Double]? = nil) throws -> UsagiState {
    let now = try reportDate("2026-10-24T08:00:00Z")
    let base = try reportState(at: now)
    var object = try #require(JSONSerialization.jsonObject(with: HealthReportCoding.encoder().encode(base)) as? [String: Any])
    object["mealHistory"] = (0..<count).map { _ -> [String: Any] in
        var meal: [String: Any] = ["id": UUID().uuidString, "name": "Meal", "calories": 5_000,
                                   "source": "manual", "recordedAt": "2026-10-24T08:00:00Z"]
        if let nutrients { meal["nutrients"] = nutrients }
        return meal
    }
    object["totalFoodCalories"] = count * 5_000
    return try HealthReportCoding.decoder().decode(UsagiState.self, from: JSONSerialization.data(withJSONObject: object))
}

@Test func reportRequestRejectsTooManyRecordsWithoutTruncating() throws {
    let now = try reportDate("2026-10-24T08:00:00Z")
    let state = try reportStateWithMeals(1_001)
    #expect(throws: HealthReportError.tooManyRecords) {
        _ = try HealthReportRequest.make(state: state, period: .month, anchorDate: "2026-10-24", now: now)
    }
    #expect(state.mealHistory.count == 1_001)
}

@Test func reportRequestRejectsOversizedEncodedBody() throws {
    let now = try reportDate("2026-10-24T08:00:00Z")
    var state = try reportStateWithMeals(1_000, nutrients: ["carbohydratesG": 1.2345678901234567e-200,
                                                         "proteinG": 1.2345678901234567e-200, "fatG": 1.2345678901234567e-200])
    for _ in 0..<200 {
        let session = try state.startWorkout(mode: .outdoor, now: now.addingTimeInterval(-3_600))
        try state.finishWorkout(durationMinutes: 1_440, repetitions: 100_000, distanceMeters: 1.2345678901234567e-200,
                                calories: 10_000, now: now, sessionID: session.id, activity: .stretching)
    }
    let uncapped = HealthReportRequest(period: .month, anchorDate: "2026-10-24", timeZone: TimeZone.current.identifier,
                                      goals: .init(steps: 6_000, calorieMinimum: nil, calorieMaximum: nil),
                                      data: .init(meals: state.mealHistory.map(HealthReportRequest.Meal.init),
                                                  workouts: state.workouts.map(HealthReportRequest.Workout.init), wellness: []))
    #expect(try HealthReportCoding.encoder().encode(uncapped).count > 262_144)
    #expect(throws: HealthReportError.requestTooLarge) {
        _ = try HealthReportRequest.make(state: state, period: .month, anchorDate: "2026-10-24", now: now)
    }
}

private let reportFixture = #"""
{
  "data": {
    "id":"6da52a91-6155-4123-b328-749899266a58","period":"week","anchorDate":"2026-10-24","timeZone":"Asia/Seoul",
    "status":"completed","createdAt":"2026-10-24T06:00:00.456Z","model":"gpt-5.6-luna","failureCode":null,
    "metrics":{
      "window":{"startDate":"2026-10-19","endDate":"2026-10-25","observedThroughDate":"2026-10-24","dayCount":7,"elapsedDays":6,"timeZone":"Asia/Seoul"},
      "food":{"loggedDays":1,"mealCount":1},
      "exercise":{"sessionCount":1,"totalMinutes":30,"totalRepetitions":null,"byActivity":[{"activity":null,"sessions":1,"totalMinutes":30}]},
      "nutrition":{"trackedMeals":0,"totalMeals":1,"carbohydratesG":null,"proteinG":null,"fatG":null,"carbohydratePercent":null,"proteinPercent":null,"fatPercent":null},
      "calories":{"totalKcal":500,"averagePerLoggedDay":500,"loggedDays":1},
      "wellness":{"sleepLoggedDays":0,"averageSleepMinutes":null,"conditionLoggedDays":0,"averageCondition":null}
    },
    "evaluation":"푸루(기록한 하루와 운동 한 번을 확인했어. 다른 날은 기록이 없어.)",
    "recommendations":[{"title":"식사 기록","detail":"먹은 음식의 양을 기록해 봐."},{"title":"수면 기록","detail":"잠든 시간을 적어 봐."},{"title":"컨디션 기록","detail":"오늘의 컨디션을 골라 봐."}]
  }
}
"""#

@Test func reportResponseDecodesFractionsAndPreservesMissingData() throws {
    let report = try HealthReportCoding.decoder().decode(HealthReportResponse.self, from: Data(reportFixture.utf8)).data
    try report.validate()
    #expect(report.status == .completed && report.recommendations.count == 3)
    #expect(report.metrics.nutrition.carbohydratePercent == nil)
    #expect(report.metrics.wellness.averageSleepMinutes == nil)
    #expect(report.metrics.exercise.byActivity.first?.activity == nil)
    #expect(abs(report.createdAt.timeIntervalSince1970.truncatingRemainder(dividingBy: 1) - 0.456) < 0.001)
    let restored = try HealthReportCoding.decoder().decode(HealthReportResource.self, from: HealthReportCoding.encoder().encode(report))
    try restored.validate()
    #expect(restored == report)
}

@Test func reportResponseRejectsInvalidNarrativeAndMetrics() throws {
    var object = try #require(JSONSerialization.jsonObject(with: Data(reportFixture.utf8)) as? [String: Any])
    var resource = try #require(object["data"] as? [String: Any])
    resource["recommendations"] = [["title": "Same", "detail": "One"], ["title": " same ", "detail": "Two"], ["title": "Third", "detail": "Three"]]
    object["data"] = resource
    let duplicate = try HealthReportCoding.decoder().decode(HealthReportResponse.self, from: JSONSerialization.data(withJSONObject: object)).data
    #expect(throws: HealthReportError.invalidResponse) { try duplicate.validate() }
    let wrongPeriod = reportFixture.replacingOccurrences(of: "\"period\":\"week\"", with: "\"period\":\"month\"")
    let wrong = try HealthReportCoding.decoder().decode(HealthReportResponse.self, from: Data(wrongPeriod.utf8)).data
    #expect(throws: HealthReportError.invalidResponse) { try wrong.validate() }
    let wrongCount = reportFixture.replacingOccurrences(of: "\"loggedDays\":1", with: "\"loggedDays\":8")
    let invalid = try HealthReportCoding.decoder().decode(HealthReportResponse.self, from: Data(wrongCount.utf8)).data
    #expect(throws: HealthReportError.invalidResponse) { try invalid.validate() }
    let futureCutoff = reportFixture.replacingOccurrences(of: "\"observedThroughDate\":\"2026-10-24\"", with: "\"observedThroughDate\":\"2026-10-25\"")
        .replacingOccurrences(of: "\"elapsedDays\":6", with: "\"elapsedDays\":7")
    let future = try HealthReportCoding.decoder().decode(HealthReportResponse.self, from: Data(futureCutoff.utf8)).data
    #expect(throws: HealthReportError.invalidResponse) { try future.validate() }
}

@Test(arguments: ["2026-10-24T06:00:00", "2026-02-30T06:00:00Z", "not-a-date"])
func reportResponseRejectsInvalidTimestamps(timestamp: String) throws {
    let fixture = reportFixture.replacingOccurrences(of: "2026-10-24T06:00:00.456Z", with: timestamp)
    #expect(throws: DecodingError.self) { try HealthReportCoding.decoder().decode(HealthReportResponse.self, from: Data(fixture.utf8)) }
}

@Test func reportResponseRejectsUnknownEnums() {
    let fixture = reportFixture.replacingOccurrences(of: "\"status\":\"completed\"", with: "\"status\":\"unknown\"")
    #expect(throws: DecodingError.self) { try HealthReportCoding.decoder().decode(HealthReportResponse.self, from: Data(fixture.utf8)) }
}

@Test func reportResponseAllowsRoundedGramDisplayWithKnownEnergyShares() throws {
    let fixture = reportFixture.replacingOccurrences(of: "\"trackedMeals\":0", with: "\"trackedMeals\":1")
        .replacingOccurrences(of: "\"carbohydratesG\":null", with: "\"carbohydratesG\":0")
        .replacingOccurrences(of: "\"proteinG\":null", with: "\"proteinG\":0")
        .replacingOccurrences(of: "\"fatG\":null", with: "\"fatG\":0")
        .replacingOccurrences(of: "\"carbohydratePercent\":null", with: "\"carbohydratePercent\":33.3")
        .replacingOccurrences(of: "\"proteinPercent\":null", with: "\"proteinPercent\":33.3")
        .replacingOccurrences(of: "\"fatPercent\":null", with: "\"fatPercent\":33.4")
    let report = try HealthReportCoding.decoder().decode(HealthReportResponse.self, from: Data(fixture.utf8))
    try report.validate()
}

@Test func reportListsRejectDuplicateIDsAndInvalidCursor() throws {
    let report = try HealthReportCoding.decoder().decode(HealthReportResponse.self, from: Data(reportFixture.utf8)).data
    let duplicate = HealthReportListResponse(data: [report, report], meta: .init(nextCursor: nil))
    #expect(throws: HealthReportError.invalidResponse) { try duplicate.validate() }
    let cursor = HealthReportListResponse(data: [report], meta: .init(nextCursor: String(repeating: "x", count: 513)))
    #expect(throws: HealthReportError.invalidResponse) { try cursor.validate() }
}
