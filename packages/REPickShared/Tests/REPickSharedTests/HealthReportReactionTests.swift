import Foundation
import Testing
@testable import REPickShared

private let legacyReactionFixture = #"""
{
  "id":"6da52a91-6155-4123-b328-749899266a58","period":"week","anchorDate":"2026-10-24","timeZone":"Asia/Seoul",
  "status":"completed","createdAt":"2026-10-24T06:00:00.456Z","model":"test-model","failureCode":null,
  "metrics":{
    "window":{"startDate":"2026-10-19","endDate":"2026-10-25","observedThroughDate":"2026-10-24","dayCount":7,"elapsedDays":6,"timeZone":"Asia/Seoul"},
    "food":{"loggedDays":1,"mealCount":1},
    "exercise":{"sessionCount":0,"totalMinutes":0,"totalRepetitions":null,"byActivity":[]},
    "nutrition":{"trackedMeals":0,"totalMeals":1,"carbohydratesG":null,"proteinG":null,"fatG":null,"carbohydratePercent":null,"proteinPercent":null,"fatPercent":null},
    "calories":{"totalKcal":500,"averagePerLoggedDay":500,"loggedDays":1},
    "wellness":{"sleepLoggedDays":0,"averageSleepMinutes":null,"conditionLoggedDays":0,"averageCondition":null}
  },
  "evaluation":"푸루(기록을 같이 살펴봤어!) 기록이 없는 날은 알 수 없어.",
  "recommendations":[{"title":"식사 기록","detail":"먹은 음식의 양을 기록해 봐."},{"title":"수면 기록","detail":"잠든 시간을 적어 봐."},{"title":"컨디션 기록","detail":"오늘의 컨디션을 골라 봐."}]
}
"""#

@Test(arguments: HealthReportReaction.allCases)
func reportReactionSurvivesAPIAndCacheCoding(_ reaction: HealthReportReaction) throws {
    let resource = legacyReactionFixture.replacingOccurrences(of: "\"failureCode\":null", with: "\"failureCode\":null,\"reaction\":\"\(reaction.rawValue)\"")
    let response = Data("{\"data\":\(resource)}".utf8)
    let report = try HealthReportCoding.decoder().decode(HealthReportResponse.self, from: response).data
    try report.validate()
    #expect(report.reaction == reaction)
    let cache = try HealthReportCoding.encoder().encode([report])
    let restored = try HealthReportCoding.decoder().decode([HealthReportResource].self, from: cache)
    #expect(restored == [report])
}

@Test(arguments: [false, true])
func legacyReportReactionCanBeMissingOrNull(explicitNull: Bool) throws {
    let resource = explicitNull
        ? legacyReactionFixture.replacingOccurrences(of: "\"failureCode\":null", with: "\"failureCode\":null,\"reaction\":null")
        : legacyReactionFixture
    let cache = Data("[\(resource)]".utf8)
    let report = try #require(HealthReportCoding.decoder().decode([HealthReportResource].self, from: cache).first)
    try report.validate()
    #expect(report.reaction == nil)
    let existingInitializer = HealthReportResource(id: report.id, period: report.period, anchorDate: report.anchorDate,
                                                  timeZone: report.timeZone, status: report.status, createdAt: report.createdAt,
                                                  model: report.model, metrics: report.metrics, evaluation: report.evaluation,
                                                  recommendations: report.recommendations, failureCode: report.failureCode)
    #expect(existingInitializer == report)
}

@Test func reportReactionRejectsUnknownWireValue() {
    let resource = legacyReactionFixture.replacingOccurrences(of: "\"failureCode\":null", with: "\"failureCode\":null,\"reaction\":\"angry\"")
    #expect(throws: DecodingError.self) {
        _ = try HealthReportCoding.decoder().decode(HealthReportResource.self, from: Data(resource.utf8))
    }
}
