import Observation
import PhotosUI
import REPickShared
import SwiftUI

struct FoodNutritionDraft {
    var name: String
    var portion: String
    var calories: String
    var carbohydrates: String
    var protein: String
    var fat: String

    init() {
        name = ""
        portion = ""
        calories = ""
        carbohydrates = ""
        protein = ""
        fat = ""
    }

    init(_ food: FoodEstimate) {
        name = food.name
        portion = food.portion
        calories = String(food.calories)
        let decimal = Locale.current.decimalSeparator ?? "."
        carbohydrates = String(food.nutrients.carbohydratesG).replacingOccurrences(of: ".", with: decimal)
        protein = String(food.nutrients.proteinG).replacingOccurrences(of: ".", with: decimal)
        fat = String(food.nutrients.fatG).replacingOccurrences(of: ".", with: decimal)
    }

    func nutrients() throws -> MealNutrients {
        guard let result = try MealNutrientInput.parse(carbohydrates: carbohydrates, protein: protein, fat: fat) else {
            throw FoodPhotoAnalysisError.invalidEstimate
        }
        return result
    }

    func estimate(notes: String, eatingStyle: FoodEatingStyle? = nil) throws -> FoodEstimate {
        guard let amount = Int(calories.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw FoodPhotoAnalysisError.invalidEstimate
        }
        return try FoodEstimate(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                portion: portion.trimmingCharacters(in: .whitespacesAndNewlines),
                                calories: amount, nutrients: nutrients(), notes: notes, eatingStyle: eatingStyle)
    }

    var macroEnergy: Double? {
        guard let nutrients = try? nutrients() else { return nil }
        return nutrients.carbohydratesG * 4 + nutrients.proteinG * 4 + nutrients.fatG * 9
    }
}

@Observable @MainActor
final class FoodCaloriesModel {
    enum Stage { case capture, preview, confirmation, review, saved }

    private(set) var stage = Stage.capture
    private(set) var photo: PreparedFoodPhoto?
    private(set) var analysis: FoodPhotoAnalysis?
    private(set) var selectedFood: FoodEstimate?
    private(set) var selectedCandidateIndex = 0
    private(set) var selectedMealKind = MealKind.breakfast
    private(set) var photoMealKind: MealKind?
    var draft: FoodNutritionDraft?
    private(set) var isImporting = false
    private(set) var isAnalyzing = false
    private(set) var isSaving = false
    var errorMessage: String?
    private var isActive = false
    private var operation: Task<Void, Never>?
    private var operationID = UUID()

    var eatingStyle: FoodEatingStyle { selectedFood?.eatingStyle ?? .rice }

    var foodCandidates: [FoodEstimate] {
        guard let analysis, let food = analysis.food else { return [] }
        return [food] + analysis.alternatives
    }

    var displayedFood: FoodEstimate? {
        guard let draft else { return selectedFood }
        return try? draft.estimate(notes: selectedFood?.notes ?? "", eatingStyle: selectedFood?.eatingStyle)
    }

    var isDraftEdited: Bool { displayedFood != selectedFood }

    func selectMealKind(_ kind: MealKind) {
        guard !isImporting, !isAnalyzing, !isSaving else { return }
        selectedMealKind = kind
        if photo != nil { photoMealKind = kind }
    }

    func selectCandidate(_ index: Int) {
        guard stage == .confirmation, !isSaving, foodCandidates.indices.contains(index),
              index != selectedCandidateIndex else { return }
        selectedCandidateIndex = index
        selectedFood = foodCandidates[index]
        draft = selectedFood.map(FoodNutritionDraft.init)
        errorMessage = nil
    }

    func importPhoto(_ item: PhotosPickerItem) {
        guard isActive, !isSaving else { return }
        cancelPending()
        let current = operationID
        let kind = selectedMealKind
        errorMessage = nil
        isImporting = true
        operation = Task {
            defer { if operationID == current { isImporting = false; operation = nil } }
            do {
                guard let imported = try await item.loadTransferable(type: FoodPhotoImport.self) else {
                    throw FoodPhotoAnalysisError.invalidImage
                }
                try Task.checkCancellation()
                guard operationID == current else { return }
                setPhoto(imported.photo, kind: kind)
            } catch is CancellationError {
            } catch {
                guard operationID == current, !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    func acceptPhoto(_ photo: PreparedFoodPhoto, kind: MealKind? = nil) {
        guard isActive, !isSaving else { return }
        cancelPending()
        setPhoto(photo, kind: kind ?? selectedMealKind)
    }

    func analyze(baseURL: String) {
        guard isActive, stage == .preview, let photo, !isAnalyzing, !isImporting, !isSaving else { return }
        cancelPending()
        let current = operationID
        errorMessage = nil
        isAnalyzing = true
        operation = Task {
            defer { if operationID == current { isAnalyzing = false; operation = nil } }
            do {
                let client = try HealthReportClient(baseURL: baseURL)
                let result = try await client.analyzeFoodPhoto(photo.request)
                try Task.checkCancellation()
                guard operationID == current else { return }
                analysis = result
                selectedFood = result.food
                selectedCandidateIndex = 0
                draft = result.food.map(FoodNutritionDraft.init)
                stage = .confirmation
            } catch is CancellationError {
            } catch {
                guard operationID == current, !Task.isCancelled else { return }
                switch error {
                case ReportClientError.setupRequired:
                    errorMessage = String(localized: "음식 분석 서버에 아직 연결되지 않았어요. 설정에서 서버 주소를 확인해 주세요.")
                case ReportClientError.invalidAddress:
                    errorMessage = String(localized: "음식 분석 서버 주소를 확인해 주세요.")
                default:
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    func confirmFood() {
        guard stage == .confirmation, !isSaving else { return }
        if draft == nil { draft = FoodNutritionDraft() }
        errorMessage = nil
        stage = .review
    }

    func back() {
        guard !isSaving else { return }
        cancelPending()
        errorMessage = nil
        switch stage {
        case .review: stage = .confirmation
        case .confirmation: stage = .preview
        case .preview: reset()
        case .capture, .saved: break
        }
    }

    func reset() {
        guard !isSaving else { return }
        cancelPending()
        photo = nil
        analysis = nil
        selectedFood = nil
        selectedCandidateIndex = 0
        photoMealKind = nil
        draft = nil
        errorMessage = nil
        stage = .capture
    }

    func cancelPending() {
        operationID = UUID()
        operation?.cancel()
        operation = nil
        isImporting = false
        isAnalyzing = false
    }

    func setActive(_ active: Bool) {
        isActive = active
        if !active { cancelPending() }
    }

    func beginPhotoSelection() -> UUID {
        cancelPending()
        return operationID
    }

    func selectionIsCurrent(_ id: UUID) -> Bool { isActive && operationID == id }

    func register(in store: UsagiStore) {
        guard isActive, [.confirmation, .review].contains(stage), !isSaving,
              let analysis, let draft, let kind = photoMealKind else { return }
        guard !store.isSaving else {
            errorMessage = String(localized: "다른 기록을 저장하고 있어요. 잠시 후 다시 등록해 주세요.")
            return
        }
        do {
            let edited = try draft.estimate(notes: selectedFood?.notes ?? "", eatingStyle: selectedFood?.eatingStyle)
            let source: MealSource = edited == selectedFood ? .photoAI : .manual
            let name = "\(edited.name) · \(edited.portion)"
            guard name.count <= 120 else {
                errorMessage = String(localized: "음식 이름과 먹은 양을 합쳐 120자 이내로 입력해 주세요.")
                return
            }
            errorMessage = nil
            isSaving = true
            Task {
                defer { isSaving = false }
                let saved = await store.update {
                    try $0.addMeal(name: name, calories: edited.calories, source: source,
                                   nutrients: edited.nutrients, id: analysis.id, kind: kind)
                }
                if saved { stage = .saved }
                else {
                    errorMessage = store.errorMessage ?? String(localized: "기록을 저장하지 못했어요. 입력한 내용은 유지됩니다. 다시 등록해 주세요.")
                }
            }
        } catch { errorMessage = error.localizedDescription }
    }

    private func setPhoto(_ photo: PreparedFoodPhoto, kind: MealKind) {
        self.photo = photo
        photoMealKind = kind
        selectedMealKind = kind
        analysis = nil
        selectedFood = nil
        selectedCandidateIndex = 0
        draft = nil
        errorMessage = nil
        stage = .preview
    }
}
