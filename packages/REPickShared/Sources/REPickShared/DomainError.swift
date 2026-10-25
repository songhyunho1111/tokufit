import Foundation

public enum DomainError: Error, LocalizedError, Equatable, Sendable {
    case invalidProfile, invalidGoal, invalidSteps, invalidMeal, invalidWater
    case profileRequired, goalIncomplete, rewardAlreadyClaimed, insufficientPoints
    case dailyDrawLimit, invalidOutfit, alreadyOwned, invalidSave, unsupportedVersion
    case invalidPreferences, invalidCalorieRange, invalidWorkout, workoutAlreadyActive, noActiveWorkout
    case invalidNutrients, invalidWellness

    public var errorDescription: String? {
        switch self {
        case .invalidProfile: String(localized: "error.profile", bundle: .module)
        case .invalidGoal: String(localized: "error.goal", bundle: .module)
        case .invalidSteps: String(localized: "error.steps", bundle: .module)
        case .invalidMeal: String(localized: "error.meal", bundle: .module)
        case .invalidWater: String(localized: "error.water", bundle: .module)
        case .profileRequired: String(localized: "error.profileRequired", bundle: .module)
        case .goalIncomplete: String(localized: "error.goalIncomplete", bundle: .module)
        case .rewardAlreadyClaimed: String(localized: "error.rewardClaimed", bundle: .module)
        case .insufficientPoints: String(localized: "error.points", bundle: .module)
        case .dailyDrawLimit: String(localized: "error.drawLimit", bundle: .module)
        case .invalidOutfit: String(localized: "error.outfit", bundle: .module)
        case .alreadyOwned: String(localized: "error.owned", bundle: .module)
        case .invalidSave: String(localized: "error.save", bundle: .module)
        case .unsupportedVersion: String(localized: "error.version", bundle: .module)
        case .invalidPreferences: String(localized: "error.preferences", bundle: .module)
        case .invalidCalorieRange: String(localized: "error.calorieRange", bundle: .module)
        case .invalidWorkout: String(localized: "error.workout", bundle: .module)
        case .workoutAlreadyActive: String(localized: "error.workoutActive", bundle: .module)
        case .noActiveWorkout: String(localized: "error.noWorkout", bundle: .module)
        case .invalidNutrients: String(localized: "error.nutrients", bundle: .module)
        case .invalidWellness: String(localized: "error.wellness", bundle: .module)
        }
    }
}
