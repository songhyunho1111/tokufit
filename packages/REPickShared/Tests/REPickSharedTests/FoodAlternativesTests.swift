import Foundation
import Testing
@testable import REPickShared

@Suite struct FoodAlternativesTests {
    private func estimate(_ name: String = "비빔국수", calories: Int = 520,
                          style: FoodEatingStyle? = .noodles) throws -> FoodEstimate {
        try FoodEstimate(name: name, portion: "약 한 그릇", calories: calories,
                         nutrients: MealNutrients(carbohydratesG: 89, proteinG: 14, fatG: 12),
                         notes: "양념과 면의 양에 따라 달라져요.", eatingStyle: style)
    }

    private func analysis(_ alternatives: [FoodEstimate] = []) throws -> FoodPhotoAnalysis {
        try FoodPhotoAnalysis(id: UUID(), createdAt: Date(timeIntervalSince1970: 1_792_800_000),
                              model: "gpt-5.6-luna", status: .recognized, food: estimate(),
                              message: "사진으로 추정한 값이에요. 음식과 양을 확인해 주세요.", alternatives: alternatives)
    }

    @Test func completeCandidatesRoundTripWithOwnNutritionAndMotion() throws {
        let candidate = try FoodEstimate(name: "볶음밥", portion: "약 한 접시", calories: 640,
                                         nutrients: MealNutrients(carbohydratesG: 92, proteinG: 20, fatG: 21),
                                         notes: "밥 종류와 기름의 양을 확인해 주세요.", eatingStyle: .rice)
        let original = try analysis([candidate, estimate("쫄면", calories: 610)])
        let data = try HealthReportCoding.encoder().encode(original)
        let decoded = try HealthReportCoding.decoder().decode(FoodPhotoAnalysis.self, from: data)
        try decoded.validate()
        #expect(decoded == original)
        #expect(decoded.alternatives[0] == candidate)
        #expect(decoded.alternatives[0].nutrients != decoded.food?.nutrients)
        #expect(decoded.alternatives[0].eatingStyle == .rice)
    }

    @Test func legacyInitializerMissingAndNullArrayStayEmpty() throws {
        let original = try FoodPhotoAnalysis(id: UUID(), createdAt: Date(), model: "legacy",
                                             status: .recognized, food: estimate(style: nil),
                                             message: "음식과 양을 확인해 주세요.")
        #expect(original.alternatives.isEmpty)
        let encoded = try HealthReportCoding.encoder().encode(original)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        for value in [nil, NSNull()] as [Any?] {
            object["alternatives"] = value
            let data = try JSONSerialization.data(withJSONObject: object)
            let decoded = try HealthReportCoding.decoder().decode(FoodPhotoAnalysis.self, from: data)
            try decoded.validate()
            #expect(decoded.alternatives.isEmpty)
            #expect(decoded.food?.eatingStyle == nil)
        }
    }

    @Test func boundsStatusAndContradictoryNamesAreRejected() throws {
        let candidate = try estimate("쫄면", calories: 610)
        #expect(throws: FoodPhotoAnalysisError.self) {
            try analysis([candidate, estimate("비빔냉면"), estimate("막국수")])
        }
        #expect(throws: FoodPhotoAnalysisError.self) {
            try analysis([estimate(" 비빔 국수 ", calories: 900)])
        }
        #expect(throws: FoodPhotoAnalysisError.self) {
            try analysis([candidate, estimate("쫄면", calories: 900)])
        }
        #expect(throws: FoodPhotoAnalysisError.self) {
            try analysis([estimate("쫄면", style: nil)])
        }
        #expect(throws: FoodPhotoAnalysisError.self) {
            try FoodPhotoAnalysis(id: UUID(), createdAt: Date(), model: "test", status: .unrecognized,
                                  food: nil, message: "선명한 음식 사진을 선택해 주세요.", alternatives: [candidate])
        }
        let unrecognized = try FoodPhotoAnalysis(id: UUID(), createdAt: Date(), model: "test", status: .unrecognized,
                                                 food: nil, message: "선명한 음식 사진을 선택해 주세요.")
        #expect(unrecognized.alternatives.isEmpty)
    }

    @Test func malformedCandidateAndInvalidDecodedNutrientsFail() throws {
        let encoded = try HealthReportCoding.encoder().encode(analysis([estimate("쫄면")]))
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["alternatives"] = "쫄면"
        #expect(throws: DecodingError.self) {
            try HealthReportCoding.decoder().decode(FoodPhotoAnalysis.self,
                                                    from: JSONSerialization.data(withJSONObject: object))
        }
        let estimateData = try JSONEncoder().encode(estimate("쫄면"))
        var candidate = try #require(JSONSerialization.jsonObject(with: estimateData) as? [String: Any])
        candidate["nutrients"] = ["carbohydratesG": 1, "proteinG": 1]
        object["alternatives"] = [candidate]
        #expect(throws: DecodingError.self) {
            try HealthReportCoding.decoder().decode(FoodPhotoAnalysis.self,
                                                    from: JSONSerialization.data(withJSONObject: object))
        }
        candidate["nutrients"] = ["carbohydratesG": 1, "proteinG": 2_001, "fatG": 1]
        object["alternatives"] = [candidate]
        let decoded = try HealthReportCoding.decoder().decode(FoodPhotoAnalysis.self,
                                                              from: JSONSerialization.data(withJSONObject: object))
        #expect(throws: DomainError.self) { try decoded.validate() }
    }
}
