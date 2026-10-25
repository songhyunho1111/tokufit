// Run with python3 tools/check_food_selection.py; no simulator, network or owner data is touched.
import Foundation
import REPickShared

enum ReportClientError: Error { case setupRequired, invalidAddress, failed }

@MainActor struct PhotosPickerItem {
    let photo: PreparedFoodPhoto
    var delay: Duration = .milliseconds(20)

    func loadTransferable(type: FoodPhotoImport.Type) async throws -> FoodPhotoImport? {
        try await Task.sleep(for: delay)
        return FoodPhotoImport(photo: photo)
    }
}

@MainActor struct HealthReportClient {
    static var result: FoodPhotoAnalysis?
    static var failure: ReportClientError?
    static var delay: Duration = .milliseconds(20)

    init(baseURL: String) throws {
        if baseURL.isEmpty { throw ReportClientError.setupRequired }
    }

    func analyzeFoodPhoto(_ request: FoodPhotoAnalysisRequest) async throws -> FoodPhotoAnalysis {
        try request.validate()
        try await Task.sleep(for: Self.delay)
        if let failure = Self.failure { throw failure }
        guard let result = Self.result else { throw FoodPhotoAnalysisError.invalidResponse }
        return result
    }
}

@MainActor final class UsagiStore {
    var state = UsagiState()
    var isSaving = false
    var errorMessage: String?
    var failNextSave = false

    func update(_ change: (inout UsagiState) throws -> Void) async -> Bool {
        isSaving = true
        defer { isSaving = false }
        if failNextSave {
            failNextSave = false
            errorMessage = "Isolated save failure"
            return false
        }
        do {
            var candidate = state
            try change(&candidate)
            state = candidate
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

@main enum FoodSelectionCheck {
    @MainActor static func main() async throws {
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            checks += 1
        }
        let photo = PreparedFoodPhoto(jpegData: Data([0xff, 0xd8, 0xff, 0x00]))
        let original = try FoodEstimate(name: "채소 샐러드", portion: "한 접시", calories: 210,
            nutrients: .init(carbohydratesG: 20, proteinG: 10, fatG: 10), notes: "샐러드 추정", eatingStyle: .grass)
        let alternative = try FoodEstimate(name: "비빔국수", portion: "반 그릇", calories: 390,
            nutrients: .init(carbohydratesG: 62, proteinG: 13, fatG: 10), notes: "국수 대안 추정", eatingStyle: .noodles)
        let analysis = try FoodPhotoAnalysis(id: UUID(), createdAt: Date(), model: "isolated-fixture",
            status: .recognized, food: original, message: "음식과 양을 확인해 주세요.", alternatives: [alternative])
        HealthReportClient.result = analysis
        let store = UsagiStore()
        try store.state.setProfile(heightCM: 170, weightKG: 70, targetWeightKG: 65, goalSteps: 6_000)
        let model = FoodCaloriesModel()
        model.setActive(true)
        model.selectMealKind(.lunch)
        model.importPhoto(PhotosPickerItem(photo: photo))
        model.selectMealKind(.dinner)
        check(model.isImporting && model.selectedMealKind == .lunch, "An in-flight import must freeze its meal kind")
        await waitUntil { !model.isImporting }
        check(model.stage == .preview && model.photoMealKind == .lunch, "Imported photo must retain the captured lunch kind")
        model.selectMealKind(.dinner)
        check(model.photoMealKind == .dinner, "An explicit meal-kind correction must update this photo's draft")
        model.analyze(baseURL: "fixture")
        model.selectMealKind(.snack)
        await waitUntil { !model.isAnalyzing }
        check(model.stage == .confirmation && model.photoMealKind == .dinner, "Analysis must retain the photo's kind")
        check(model.foodCandidates == [original, alternative] && model.selectedCandidateIndex == 0,
              "Primary and alternative estimates must remain complete, ordered candidates")
        check(model.displayedFood == original && model.eatingStyle == .grass, "Initial display must use the actual primary estimate")
        model.selectCandidate(1)
        check(model.selectedFood == alternative && model.displayedFood == alternative,
              "Choosing an alternative must swap the complete name, portion, calories, macros and notes")
        check(model.eatingStyle == .noodles && model.analysis?.id == analysis.id,
              "Alternative eating style must update while retaining the same analysis ID")
        model.selectCandidate(8)
        check(model.selectedCandidateIndex == 1 && model.selectedFood == alternative, "Invalid candidate indices must be ignored")
        model.confirmFood()
        check(model.stage == .review && model.photoMealKind == .dinner, "Direct input must open the review for the same meal")
        model.draft?.name = "직접 수정한 국수"
        model.draft?.calories = "410"
        model.draft?.carbohydrates = "45"
        model.draft?.protein = "20"
        model.draft?.fat = "15"
        model.back()
        check(model.stage == .confirmation && model.displayedFood?.calories == 410
              && model.displayedFood?.name == "직접 수정한 국수" && model.isDraftEdited,
              "Back to result must show the edited draft instead of stale AI values")
        model.confirmFood()
        check(model.draft?.calories == "410" && model.draft?.carbohydrates == "45", "Review/back must retain manual input")
        store.failNextSave = true
        model.register(in: store)
        await waitUntil { !model.isSaving }
        check(model.stage == .review && store.state.daily.meals.isEmpty && model.errorMessage != nil,
              "A failed save must keep the draft and must not show a saved state")
        check(model.analysis?.id == analysis.id && model.photoMealKind == .dinner, "Failed-save retry must keep the ID and meal kind")
        model.register(in: store)
        model.register(in: store)
        await waitUntil { !model.isSaving }
        check(model.stage == .saved && store.state.daily.meals.count == 1, "Repeated register taps must save once")
        let meal = store.state.daily.meals[0]
        let editedNutrients = try MealNutrients(carbohydratesG: 45, proteinG: 20, fatG: 15)
        check(meal.id == analysis.id && meal.kind == .dinner && meal.source == .manual,
              "Edited alternative must persist with the stable ID, correct kind and manual source")
        check(meal.name == "직접 수정한 국수 · 반 그릇" && meal.calories == 410 && meal.nutrients == editedNutrients,
              "Saved meal must contain all edited values, not stale primary nutrients")
        check(model.eatingStyle == .noodles, "Saved animation must retain the chosen alternative's eating style")
        let restored = try JSONDecoder().decode(UsagiState.self, from: JSONEncoder().encode(store.state))
        check(restored.daily.meals[0] == meal, "Meal kind and source must survive persistence encoding")

        let direct = FoodCaloriesModel()
        direct.setActive(true)
        direct.acceptPhoto(photo, kind: .breakfast)
        let directAnalysis = try FoodPhotoAnalysis(id: UUID(), createdAt: Date(), model: "isolated-fixture",
            status: .recognized, food: original, message: "음식과 양을 확인해 주세요.", alternatives: [alternative])
        HealthReportClient.result = directAnalysis
        direct.analyze(baseURL: "fixture")
        await waitUntil { !direct.isAnalyzing }
        direct.selectCandidate(1)
        direct.register(in: store)
        await waitUntil { !direct.isSaving }
        let directMeal = store.state.daily.meals.last!
        check(direct.stage == .saved && directMeal.id == directAnalysis.id && directMeal.source == .photoAI,
              "Unedited selected alternative can register directly as photo AI")
        check(directMeal.calories == alternative.calories && directMeal.nutrients == alternative.nutrients
              && directMeal.kind == .breakfast, "Direct registration must use all selected alternative values and capture kind")

        let unknown = FoodCaloriesModel()
        unknown.setActive(true)
        unknown.acceptPhoto(photo, kind: .snack)
        let unknownAnalysis = try FoodPhotoAnalysis(id: UUID(), createdAt: Date(), model: "isolated-fixture",
            status: .unrecognized, food: nil, message: "음식을 확인하지 못했어요.", alternatives: [])
        HealthReportClient.result = unknownAnalysis
        unknown.analyze(baseURL: "fixture")
        await waitUntil { !unknown.isAnalyzing }
        check(unknown.foodCandidates.isEmpty && unknown.displayedFood == nil, "Unknown results must not invent food candidates")
        unknown.register(in: store)
        check(!unknown.isSaving && store.state.daily.meals.count == 2, "Unknown result cannot register invented nutrition")
        unknown.confirmFood()
        check(unknown.stage == .review && unknown.draft?.calories == "", "Unknown direct input must start with blank nutrition")
        unknown.register(in: store)
        check(!unknown.isSaving && unknown.errorMessage != nil && store.state.daily.meals.count == 2,
              "Blank manual nutrition must fail validation without storing a meal")
        unknown.draft = FoodNutritionDraft(original)
        unknown.register(in: store)
        await waitUntil { !unknown.isSaving }
        check(store.state.daily.meals.last?.source == .manual && store.state.daily.meals.last?.kind == .snack,
              "Manually supplied unknown-food nutrition must be marked manual and retain snack kind")

        let cancelled = FoodCaloriesModel()
        cancelled.setActive(true)
        cancelled.acceptPhoto(photo, kind: .lunch)
        HealthReportClient.result = analysis
        cancelled.analyze(baseURL: "fixture")
        cancelled.cancelPending()
        try await Task.sleep(for: .milliseconds(40))
        check(cancelled.stage == .preview && cancelled.analysis == nil && cancelled.photoMealKind == .lunch,
              "Cancelled analysis must not apply a late result or discard the photo's kind")
        HealthReportClient.failure = .failed
        cancelled.analyze(baseURL: "fixture")
        await waitUntil { !cancelled.isAnalyzing }
        check(cancelled.stage == .preview && cancelled.errorMessage != nil && cancelled.photoMealKind == .lunch,
              "Analysis failure must retain the photo and kind for retry")
        HealthReportClient.failure = nil
        cancelled.reset()
        check(cancelled.photo == nil && cancelled.photoMealKind == nil && cancelled.draft == nil,
              "Reset must clear the previous photo's draft and kind")
        cancelled.importPhoto(PhotosPickerItem(photo: photo))
        cancelled.setActive(false)
        try await Task.sleep(for: .milliseconds(40))
        check(cancelled.photo == nil && cancelled.stage == .capture, "Inactive tabs must not accept late photo imports")
        print("Food selection: \(checks) checks passed; full candidate swap, captured meal kind, edited source, stable save ID, retry, unknown food and cancellation.")
    }

    @MainActor private static func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        preconditionFailure("The isolated asynchronous operation did not finish")
    }
}
