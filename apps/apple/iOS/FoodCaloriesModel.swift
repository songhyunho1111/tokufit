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

    func estimate(notes: String) throws -> FoodEstimate {
        guard let amount = Int(calories.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw FoodPhotoAnalysisError.invalidEstimate
        }
        return try FoodEstimate(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                portion: portion.trimmingCharacters(in: .whitespacesAndNewlines),
                                calories: amount, nutrients: nutrients(), notes: notes)
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
    var draft: FoodNutritionDraft?
    private(set) var isImporting = false
    private(set) var isAnalyzing = false
    private(set) var isSaving = false
    var errorMessage: String?
    private var isActive = false
    private var operation: Task<Void, Never>?
    private var operationID = UUID()

    func importPhoto(_ item: PhotosPickerItem) {
        guard isActive, !isSaving else { return }
        cancelPending()
        let current = operationID
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
                setPhoto(imported.photo)
            } catch is CancellationError {
            } catch {
                guard operationID == current, !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    func acceptPhoto(_ photo: PreparedFoodPhoto) {
        guard isActive, !isSaving else { return }
        cancelPending()
        setPhoto(photo)
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
        guard stage == .confirmation, analysis?.food != nil else { return }
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
        guard isActive, stage == .review, !isSaving, let analysis, let original = analysis.food, let draft else { return }
        guard !store.isSaving else {
            errorMessage = String(localized: "다른 기록을 저장하고 있어요. 잠시 후 다시 등록해 주세요.")
            return
        }
        do {
            let edited = try draft.estimate(notes: original.notes)
            let source: MealSource = edited == original ? .photoAI : .manual
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
                                   nutrients: edited.nutrients, id: analysis.id)
                }
                if saved { stage = .saved }
                else {
                    errorMessage = store.errorMessage ?? String(localized: "기록을 저장하지 못했어요. 입력한 내용은 유지됩니다. 다시 등록해 주세요.")
                }
            }
        } catch { errorMessage = error.localizedDescription }
    }

    private func setPhoto(_ photo: PreparedFoodPhoto) {
        self.photo = photo
        analysis = nil
        draft = nil
        errorMessage = nil
        stage = .preview
    }
}
