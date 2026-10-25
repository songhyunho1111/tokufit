import Foundation

public enum MealKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case breakfast, lunch, dinner, snack
    public var id: String { rawValue }
    public var name: String {
        switch self {
        case .breakfast: String(localized: "meal.breakfast", defaultValue: "아침", bundle: .module)
        case .lunch: String(localized: "meal.lunch", defaultValue: "점심", bundle: .module)
        case .dinner: String(localized: "meal.dinner", defaultValue: "저녁", bundle: .module)
        case .snack: String(localized: "meal.snack", defaultValue: "간식", bundle: .module)
        }
    }
}

public enum NutritionMood: String, Codable, Sendable {
    case neutral, sparkling, lowEnergy
}

public enum NutritionStatus: String, Codable, Sendable {
    case unconfigured, unrecorded, below, within, above
}

public enum DailyMissionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case calorieRange, stairs, threeMeals
    public var id: String { rawValue }
}

struct DailyNutritionProgress: Codable, Equatable, Sendable {
    var minimum: Int?
    var maximum: Int?

    init(minimum: Int? = nil, maximum: Int? = nil) {
        self.minimum = minimum
        self.maximum = maximum
    }

    func validate() throws {
        switch (minimum, maximum) {
        case (nil, nil): break
        case let (.some(minimum), .some(maximum)):
            guard (0...10_000).contains(minimum), (1...10_000).contains(maximum), minimum <= maximum else {
                throw DomainError.invalidSave
            }
        default: throw DomainError.invalidSave
        }
    }
}

struct DailyMissionProgress: Codable, Equatable, Sendable {
    var stairSteps = 0
    var foodDayConfirmed = false
    var confirmedFoodCalories: Int?
    var claimed: [DailyMissionKind] = []
    var rewardPoints = 5

    func validate() throws {
        guard (0...100_000).contains(stairSteps), (5...18_260_300).contains(rewardPoints),
              rewardPoints.isMultiple(of: 5), Set(claimed).count == claimed.count else {
            throw DomainError.invalidSave
        }
    }
}

struct MissionRewardProgress: Codable, Equatable, Sendable {
    var lastQualifiedDay: String?
    var streak = 0

    func validate(currentDay: String) throws {
        if let lastQualifiedDay {
            guard UsagiState.isValidDay(lastQualifiedDay), lastQualifiedDay <= currentDay,
                  (1...3_652_059).contains(streak) else { throw DomainError.invalidSave }
        } else if streak != 0 {
            throw DomainError.invalidSave
        }
    }
}

public enum MissionError: Error, LocalizedError, Equatable, Sendable {
    case checkInRequired, incomplete, invalidStairSteps, foodDayIncomplete

    public var errorDescription: String? {
        switch self {
        case .checkInRequired:
            String(localized: "mission.checkInRequired", defaultValue: "오늘 출석체크 후 보상을 받을 수 있어요.", bundle: .module)
        case .incomplete:
            String(localized: "mission.incomplete", defaultValue: "미션을 완료한 뒤 보상을 받아 주세요.", bundle: .module)
        case .invalidStairSteps:
            String(localized: "mission.invalidStairSteps", defaultValue: "직접 확인한 계단 수를 0~100,000칸으로 입력해 주세요.", bundle: .module)
        case .foodDayIncomplete:
            String(localized: "mission.foodDayIncomplete", defaultValue: "아침·점심·저녁을 기록하고 오늘의 칼로리 범위 안에서 식사를 마무리해 주세요.", bundle: .module)
        }
    }
}
