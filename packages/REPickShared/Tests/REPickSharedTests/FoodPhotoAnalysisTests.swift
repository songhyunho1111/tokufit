import Foundation
import Testing
@testable import REPickShared

private let foodPhotoDay = Date(timeIntervalSince1970: 1_792_800_000)
private let foodPhotoID = UUID(uuidString: "4EAB0984-8096-4445-898C-997612F5A1A9")!
private let foodPhotoPNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jVQAAAABJRU5ErkJggg=="

private func foodPhotoEstimate() throws -> FoodEstimate {
    try FoodEstimate(name: "비빔밥", portion: "한 그릇", calories: 560,
                     nutrients: MealNutrients(carbohydratesG: 80.5, proteinG: 20, fatG: 17.5),
                     notes: "사진만으로 분량을 정확히 알기 어려워요.")
}

private func foodPhotoResponse(status: FoodPhotoAnalysis.Status = .recognized) throws -> FoodPhotoAnalysisResponse {
    try FoodPhotoAnalysisResponse(data: FoodPhotoAnalysis(
        id: foodPhotoID, createdAt: foodPhotoDay, model: "test-vision", status: status,
        food: status == .recognized ? foodPhotoEstimate() : nil,
        message: "추정한 음식과 분량을 확인해 주세요."
    ))
}

private func foodPhotoState() throws -> UsagiState {
    var state = UsagiState(now: foodPhotoDay)
    try state.setProfile(heightCM: 170, weightKG: 70, targetWeightKG: 65, goalSteps: 6_000)
    return state
}

@Test func foodPhotoRequestEncodesOnlyTheImageContract() throws {
    let request = try FoodPhotoAnalysisRequest(image: .init(mimeType: "image/png", base64: foodPhotoPNG))
    let encoded = try HealthReportCoding.encoder().encode(request)
    let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    #expect(Set(object.keys) == ["image"])
    let image = try #require(object["image"] as? [String: String])
    #expect(image == ["mimeType": "image/png", "base64": foodPhotoPNG])
    let decoded = try HealthReportCoding.decoder().decode(FoodPhotoAnalysisRequest.self, from: encoded)
    try decoded.validate()
    #expect(decoded == request)
}

@Test func foodPhotoRequestRejectsInvalidEncodingMimeSignaturesAndExcessBytes() throws {
    let invalid: [(String, String)] = [
        ("image/heic", foodPhotoPNG), ("image/jpeg", foodPhotoPNG), ("image/png", ""),
        ("image/png", "%%%"), ("image/png", foodPhotoPNG + "\n"),
        ("image/png", Data("not an image".utf8).base64EncodedString())
    ]
    for (mime, base64) in invalid {
        #expect(throws: FoodPhotoAnalysisError.self) {
            try FoodPhotoAnalysisRequest.Image(mimeType: mime, base64: base64)
        }
    }
    var oversized = Data([0xff, 0xd8, 0xff])
    oversized.append(Data(repeating: 0, count: FoodPhotoAnalysisRequest.Image.maximumBytes - 2))
    #expect(throws: FoodPhotoAnalysisError.self) {
        try FoodPhotoAnalysisRequest.Image(mimeType: "image/jpeg", base64: oversized.base64EncodedString())
    }
    let invalidJSON = Data(#"{"image":{"mimeType":"image/png","base64":"bm90LWFuLWltYWdl"}}"#.utf8)
    let decoded = try HealthReportCoding.decoder().decode(FoodPhotoAnalysisRequest.self, from: invalidJSON)
    #expect(throws: FoodPhotoAnalysisError.self) { try decoded.validate() }
}

@Test func foodPhotoResponsePreservesEstimateAndExplicitNullWithFractionalUTCDate() throws {
    for status in [FoodPhotoAnalysis.Status.recognized, .unrecognized] {
        let response = try foodPhotoResponse(status: status)
        let encoded = try HealthReportCoding.encoder().encode(response)
        let decoded = try HealthReportCoding.decoder().decode(FoodPhotoAnalysisResponse.self, from: encoded)
        try decoded.validate()
        #expect(decoded == response)
        let text = String(decoding: encoded, as: UTF8.self)
        #expect(text.contains(".000Z"))
        if status == .unrecognized { #expect(text.contains("\"food\":null")) }
    }
    let fractional = """
    {"data":{"id":"4EAB0984-8096-4445-898C-997612F5A1A9","createdAt":"2026-10-24T10:00:00.123Z",\
    "model":"test-vision","status":"recognized","food":{"name":"비빔밥","portion":"한 그릇",\
    "calories":560,"nutrients":{"carbohydratesG":80.5,"proteinG":20,"fatG":17.5},"notes":"추정치예요."},\
    "message":"음식과 분량을 확인해 주세요."}}
    """
    let decoded = try HealthReportCoding.decoder().decode(FoodPhotoAnalysisResponse.self, from: Data(fractional.utf8))
    try decoded.validate()
    #expect(decoded.data.food?.nutrients.carbohydratesG == 80.5)
    #expect(decoded.data.food?.calories == 560)
    #expect(abs(decoded.data.createdAt.timeIntervalSince1970.truncatingRemainder(dividingBy: 1) - 0.123) < 0.001)

    let unrecognized = try HealthReportCoding.encoder().encode(foodPhotoResponse(status: .unrecognized))
    let missingFood = String(decoding: unrecognized, as: UTF8.self).replacingOccurrences(of: "\"food\":null,", with: "")
    #expect(throws: DecodingError.self) {
        try HealthReportCoding.decoder().decode(FoodPhotoAnalysisResponse.self, from: Data(missingFood.utf8))
    }
}

@Test func foodPhotoResponseRejectsStatusMismatchAndInvalidText() throws {
    let estimate = try foodPhotoEstimate()
    #expect(throws: FoodPhotoAnalysisError.self) {
        try FoodPhotoAnalysis(id: foodPhotoID, createdAt: foodPhotoDay, model: "test", status: .recognized,
                              food: nil, message: "확인해 주세요.")
    }
    #expect(throws: FoodPhotoAnalysisError.self) {
        try FoodPhotoAnalysis(id: foodPhotoID, createdAt: foodPhotoDay, model: "test", status: .unrecognized,
                              food: estimate, message: "확인해 주세요.")
    }
    for message in ["", "   ", "Check the food", String(repeating: "가", count: 301)] {
        #expect(throws: FoodPhotoAnalysisError.self) {
            try FoodPhotoAnalysis(id: foodPhotoID, createdAt: foodPhotoDay, model: "test", status: .recognized,
                                  food: estimate, message: message)
        }
    }
    for model in ["", "  ", String(repeating: "m", count: 161)] {
        #expect(throws: FoodPhotoAnalysisError.self) {
            try FoodPhotoAnalysis(id: foodPhotoID, createdAt: foodPhotoDay, model: model, status: .recognized,
                                  food: estimate, message: "확인해 주세요.")
        }
    }
}

@Test func foodPhotoEstimateRejectsBoundsAndNeverDefaultsMissingNutrientsToZero() throws {
    let estimate = try foodPhotoEstimate()
    for calories in [0, 5_001] {
        #expect(throws: FoodPhotoAnalysisError.self) {
            try FoodEstimate(name: estimate.name, portion: estimate.portion, calories: calories,
                             nutrients: estimate.nutrients, notes: "")
        }
    }
    for text in ["", "   ", String(repeating: "가", count: 121)] {
        #expect(throws: FoodPhotoAnalysisError.self) {
            try FoodEstimate(name: text, portion: estimate.portion, calories: 560, nutrients: estimate.nutrients, notes: "")
        }
        #expect(throws: FoodPhotoAnalysisError.self) {
            try FoodEstimate(name: estimate.name, portion: text, calories: 560, nutrients: estimate.nutrients, notes: "")
        }
    }
    #expect(throws: FoodPhotoAnalysisError.self) {
        try FoodEstimate(name: estimate.name, portion: estimate.portion, calories: 560,
                         nutrients: estimate.nutrients, notes: String(repeating: "가", count: 301))
    }
    for nutrients in ["null", "{}", #"{"carbohydratesG":10,"proteinG":5}"#] {
        let json = """
        {"name":"식사","portion":"한 그릇","calories":100,"nutrients":\(nutrients),"notes":""}
        """
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(FoodEstimate.self, from: Data(json.utf8))
        }
    }
    for grams in [-1.0, 2_001, .infinity, .nan] {
        #expect(throws: DomainError.self) { try MealNutrients(carbohydratesG: grams, proteinG: 0, fatG: 0) }
    }
    let invalid = Data(#"{"name":"식사","portion":"한 그릇","calories":100,"nutrients":{"carbohydratesG":-1,"proteinG":5,"fatG":2},"notes":""}"#.utf8)
    let decoded = try JSONDecoder().decode(FoodEstimate.self, from: invalid)
    #expect(throws: DomainError.self) { try decoded.validate() }
}

@Test func foodPhotoMealRetryIsANoopAfterReloadAndDayRollover() throws {
    var state = try foodPhotoState()
    let nutrients = try foodPhotoEstimate().nutrients
    try state.addMeal(name: "비빔밥 한 그릇", calories: 560, source: .photoAI,
                      now: foodPhotoDay, nutrients: nutrients, id: foodPhotoID)
    let saved = state
    try state.addMeal(name: "  비빔밥 한 그릇  ", calories: 560, source: .photoAI,
                      now: foodPhotoDay.addingTimeInterval(60), nutrients: nutrients, id: foodPhotoID)
    #expect(state == saved)
    state = try HealthReportCoding.decoder().decode(UsagiState.self, from: HealthReportCoding.encoder().encode(state))
    state.rollover(now: foodPhotoDay.addingTimeInterval(86_400))
    let afterRollover = state
    try state.addMeal(name: "비빔밥 한 그릇", calories: 560, source: .photoAI,
                      now: foodPhotoDay.addingTimeInterval(86_460), nutrients: nutrients, id: foodPhotoID)
    #expect(state == afterRollover)
    #expect(state.daily.meals.isEmpty)
    #expect(state.mealHistory.count == 1)
    #expect(state.totalFoodCalories == 560)
    #expect(state.mealHistory.first?.recordedAt == foodPhotoDay)
    try state.validate()
}

@Test func foodPhotoMealConflictsAndInvalidNutritionLeaveStateUnchanged() throws {
    var state = try foodPhotoState()
    let nutrients = try foodPhotoEstimate().nutrients
    try state.addMeal(name: "비빔밥 한 그릇", calories: 560, source: .photoAI,
                      now: foodPhotoDay, nutrients: nutrients, id: foodPhotoID)
    let before = state
    let changedNutrients = try MealNutrients(carbohydratesG: 81, proteinG: 20, fatG: 17.5)
    let changes: [(String, Int, MealSource, MealNutrients?)] = [
        ("다른 식사", 560, .photoAI, nutrients), ("비빔밥 한 그릇", 561, .photoAI, nutrients),
        ("비빔밥 한 그릇", 560, .manual, nutrients), ("비빔밥 한 그릇", 560, .photoAI, changedNutrients),
        ("비빔밥 한 그릇", 560, .manual, nil)
    ]
    for (name, calories, source, macros) in changes {
        #expect(throws: DomainError.self) {
            try state.addMeal(name: name, calories: calories, source: source,
                              now: foodPhotoDay, nutrients: macros, id: foodPhotoID)
        }
        #expect(state == before)
    }
    #expect(throws: DomainError.self) {
        try state.addMeal(name: "정보가 누락된 식사", calories: 200, source: .photoAI, now: foodPhotoDay)
    }
    #expect(state == before)
    try state.addMeal(name: "기존 수동 식사", calories: 300, source: .manual, now: foodPhotoDay)
    #expect(state.daily.meals.count == 2)
    #expect(state.mealHistory.count == 2)
    #expect(state.totalFoodCalories == 860)
    #expect(state.daily.meals.last?.nutrients == nil)
    try state.validate()
}
