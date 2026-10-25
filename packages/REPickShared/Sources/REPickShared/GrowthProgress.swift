import Foundation

public struct AttendanceProgress: Codable, Equatable, Sendable {
    public internal(set) var lastCheckInDay: String?
    public internal(set) var streak = 0
    public internal(set) var days: [String] = []
    public internal(set) var lastRewardDay: String?

    public init() {}

    func validate(currentDay: String) throws {
        guard streak >= 0, streak <= 3_652_059, days.count <= 366,
              days == days.sorted(), Set(days).count == days.count,
              days.allSatisfy({ UsagiState.isValidDay($0) && $0 <= currentDay }) else {
            throw DomainError.invalidSave
        }
        if let lastCheckInDay {
            guard UsagiState.isValidDay(lastCheckInDay), lastCheckInDay <= currentDay, streak > 0,
                  days.last == nil || days.last == lastCheckInDay else { throw DomainError.invalidSave }
            let recent = days.suffix(min(streak, days.count))
            for (previous, next) in zip(recent, recent.dropFirst()) {
                guard Self.distance(from: previous, to: next) == 1 else { throw DomainError.invalidSave }
            }
        } else {
            guard streak == 0, days.isEmpty, lastRewardDay == nil else { throw DomainError.invalidSave }
        }
        if let lastRewardDay {
            guard UsagiState.isValidDay(lastRewardDay), let lastCheckInDay,
                  lastRewardDay <= lastCheckInDay else { throw DomainError.invalidSave }
        }
    }

    // Calendar keys stay fixed after travel; UTC here measures calendar dates, not elapsed 24-hour periods.
    static func distance(from earlier: String, to later: String) -> Int? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        func date(_ key: String) -> Date? {
            guard UsagiState.isValidDay(key) else { return nil }
            let parts = key.split(separator: "-").compactMap { Int($0) }
            return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        }
        guard let start = date(earlier), let end = date(later) else { return nil }
        return calendar.dateComponents([.day], from: start, to: end).day
    }
}

public enum GachaPayment: String, Codable, Equatable, Sendable {
    case free, points
}

public struct GachaReceipt: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let outfit: Outfit?
    public let costume: CharacterCostume?
    public let wasDuplicate: Bool
    public let payment: GachaPayment

    public var rewardName: String { costume?.name ?? outfit?.name ?? "" }

    public init(id: UUID, outfit: Outfit? = nil, costume: CharacterCostume? = nil,
                wasDuplicate: Bool, payment: GachaPayment) {
        self.id = id
        self.outfit = outfit
        self.costume = costume
        self.wasDuplicate = wasDuplicate
        self.payment = payment
    }
}

public enum GrowthError: Error, LocalizedError, Equatable, Sendable {
    case noFreeDraws, clockMovedBackward

    public var errorDescription: String? {
        switch self {
        case .noFreeDraws:
            String(localized: "growth.noFreeDraws", defaultValue: "무료 뽑기 기회가 없어요. 다시 확인해 주세요.", bundle: .module)
        case .clockMovedBackward:
            String(localized: "growth.clockMovedBackward", defaultValue: "기록된 날짜보다 이전이에요. 기기의 날짜를 확인해 주세요.", bundle: .module)
        }
    }
}

public enum WorkoutCalorieSource: String, Codable, Equatable, Sendable {
    case manual, estimated
}

public enum ExerciseEnergy {
    /// Conservative activity assumptions from the 2024 Adult Compendium; this is not a health measurement.
    /// Active kcal = (MET - 1) × kg × hours, rounded down; one resting MET is excluded.
    /// https://pacompendium.com/ defines one MET as 1 kcal/kg/hour.
    public static func estimateCalories(activity: WorkoutActivity, minutes: Int, weightKG: Double) -> Int? {
        guard (1...1_440).contains(minutes), weightKG.isFinite, (20...350).contains(weightKG) else { return nil }
        // Integer tenths avoid losing a whole kcal when a decimal MET lands just below an integer result.
        let metTenths: Int
        switch activity {
        case .walking: metTenths = 28 // Walking 2.0–2.4 mph, code 17152: https://pacompendium.com/walking/
        case .running: metTenths = 65 // Running 4.0–4.2 mph, code 12028: https://pacompendium.com/running/
        case .cycling: metTenths = 35 // Leisure/light stationary, codes 01018/01210: https://pacompendium.com/bicycling/
        case .strength: metTenths = 30 // General body-weight exercise, code 02056: https://pacompendium.com/conditioning-exercise/
        case .stretching: metTenths = 23 // Mild stretching, code 02101: https://pacompendium.com/conditioning-exercise/
        case .other: return nil
        }
        let calories = Double(metTenths - 10) * weightKG * Double(minutes) / 600
        guard calories.isFinite, (1...10_000).contains(calories) else { return nil }
        return Int(calories.rounded(.down))
    }
}
