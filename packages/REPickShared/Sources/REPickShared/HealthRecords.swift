import Foundation

public struct MealNutrients: Codable, Equatable, Sendable {
    public let carbohydratesG: Double
    public let proteinG: Double
    public let fatG: Double

    public init(carbohydratesG: Double, proteinG: Double, fatG: Double) throws {
        self.carbohydratesG = carbohydratesG
        self.proteinG = proteinG
        self.fatG = fatG
        try validate()
    }

    public func validate() throws {
        guard [carbohydratesG, proteinG, fatG].allSatisfy({ $0.isFinite && (0...2_000).contains($0) }) else {
            throw DomainError.invalidNutrients
        }
    }
}

public struct WellnessEntry: Codable, Equatable, Identifiable, Sendable {
    public let day: String
    public let sleepMinutes: Int?
    public let condition: Int?
    public var id: String { day }

    public init(day: String, sleepMinutes: Int? = nil, condition: Int? = nil) throws {
        self.day = day
        self.sleepMinutes = sleepMinutes
        self.condition = condition
        try validate()
    }

    public func validate() throws {
        guard UsagiState.isValidDay(day), sleepMinutes != nil || condition != nil,
              sleepMinutes.map({ (0...1_440).contains($0) }) ?? true,
              condition.map({ (1...5).contains($0) }) ?? true else {
            throw DomainError.invalidWellness
        }
    }
}

public enum WorkoutActivity: String, Codable, CaseIterable, Identifiable, Sendable {
    case walking, running, cycling, strength, stretching, other
    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .walking: String(localized: "activity.walking", bundle: .module)
        case .running: String(localized: "activity.running", bundle: .module)
        case .cycling: String(localized: "activity.cycling", bundle: .module)
        case .strength: String(localized: "activity.strength", bundle: .module)
        case .stretching: String(localized: "activity.stretching", bundle: .module)
        case .other: String(localized: "activity.other", bundle: .module)
        }
    }
}
