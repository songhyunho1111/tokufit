import Foundation

public enum CharacterKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case usagi, chiikawa, hachiware
    public var id: String { rawValue }
    public var name: String {
        switch self {
        case .usagi: String(localized: "character.usagi", bundle: .module)
        case .chiikawa: String(localized: "character.chiikawa", bundle: .module)
        case .hachiware: String(localized: "character.hachiware", bundle: .module)
        }
    }
}

public enum HomeMetric: String, Codable, CaseIterable, Identifiable, Sendable {
    case steps, calories, water, workoutMinutes, weightChange
    public var id: String { rawValue }
    public var name: String {
        switch self {
        case .steps: String(localized: "metric.steps", bundle: .module)
        case .calories: String(localized: "metric.calories", bundle: .module)
        case .water: String(localized: "metric.water", bundle: .module)
        case .workoutMinutes: String(localized: "metric.workoutMinutes", bundle: .module)
        case .weightChange: String(localized: "metric.weightChange", bundle: .module)
        }
    }
}

public struct CompanionPreferences: Codable, Equatable, Sendable {
    public var name: String
    public var character: CharacterKind
    public var goalTitle: String
    public var calorieMinimum: Int?
    public var calorieMaximum: Int?
    public var homeMetrics: [HomeMetric]
    public var voiceEnabled: Bool

    public init(name: String = "우사기", character: CharacterKind = .usagi, goalTitle: String = "",
                calorieMinimum: Int? = nil, calorieMaximum: Int? = nil,
                homeMetrics: [HomeMetric] = [.steps, .calories, .water], voiceEnabled: Bool = false) {
        self.name = name
        self.character = character
        self.goalTitle = goalTitle
        self.calorieMinimum = calorieMinimum
        self.calorieMaximum = calorieMaximum
        self.homeMetrics = homeMetrics
        self.voiceEnabled = voiceEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case name, character, goalTitle, calorieMinimum, calorieMaximum, homeMetrics, voiceEnabled
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = values.contains(.name) ? try values.decode(String.self, forKey: .name) : "우사기"
        character = values.contains(.character) ? try values.decode(CharacterKind.self, forKey: .character) : .usagi
        goalTitle = values.contains(.goalTitle) ? try values.decode(String.self, forKey: .goalTitle) : ""
        calorieMinimum = try values.decodeIfPresent(Int.self, forKey: .calorieMinimum)
        calorieMaximum = try values.decodeIfPresent(Int.self, forKey: .calorieMaximum)
        homeMetrics = values.contains(.homeMetrics) ? try values.decode([HomeMetric].self, forKey: .homeMetrics) : [.steps, .calories, .water]
        voiceEnabled = values.contains(.voiceEnabled) ? try values.decode(Bool.self, forKey: .voiceEnabled) : false
    }

    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 24,
              !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              goalTitle.count <= 80,
              !goalTitle.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              (1...HomeMetric.allCases.count).contains(homeMetrics.count),
              Set(homeMetrics).count == homeMetrics.count else { throw DomainError.invalidPreferences }
        switch (calorieMinimum, calorieMaximum) {
        case (nil, nil): break
        case let (.some(minimum), .some(maximum)):
            guard (0...10_000).contains(minimum), (1...10_000).contains(maximum), minimum <= maximum else {
                throw DomainError.invalidCalorieRange
            }
        default: throw DomainError.invalidCalorieRange
        }
    }
}

public enum WardrobeCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case top, bottom, shoes, accessory
    public var id: String { rawValue }
    public var name: String {
        switch self {
        case .top: String(localized: "wardrobe.top", bundle: .module)
        case .bottom: String(localized: "wardrobe.bottom", bundle: .module)
        case .shoes: String(localized: "wardrobe.shoes", bundle: .module)
        case .accessory: String(localized: "wardrobe.accessory", bundle: .module)
        }
    }
}

public enum WardrobeItem: String, Codable, CaseIterable, Identifiable, Sendable {
    case shorts, skirt, sneakers, boots, bow, glasses
    public var id: String { rawValue }
    public var category: WardrobeCategory {
        switch self {
        case .shorts, .skirt: .bottom
        case .sneakers, .boots: .shoes
        case .bow, .glasses: .accessory
        }
    }
    public var price: Int {
        switch category {
        case .top: 500
        case .bottom: 300
        case .shoes: 250
        case .accessory: 200
        }
    }
    public var name: String {
        switch self {
        case .shorts: String(localized: "item.shorts", bundle: .module)
        case .skirt: String(localized: "item.skirt", bundle: .module)
        case .sneakers: String(localized: "item.sneakers", bundle: .module)
        case .boots: String(localized: "item.boots", bundle: .module)
        case .bow: String(localized: "item.bow", bundle: .module)
        case .glasses: String(localized: "item.glasses", bundle: .module)
        }
    }
}

public enum WorkoutMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case outdoor, indoor
    public var id: String { rawValue }
    public var name: String {
        switch self {
        case .outdoor: String(localized: "workout.outdoor", bundle: .module)
        case .indoor: String(localized: "workout.indoor", bundle: .module)
        }
    }
}

public struct WorkoutSession: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let mode: WorkoutMode
    public let startedAt: Date

    public init(id: UUID = UUID(), mode: WorkoutMode, startedAt: Date = Date()) {
        self.id = id
        self.mode = mode
        self.startedAt = Date(timeIntervalSince1970: floor(startedAt.timeIntervalSince1970))
    }

    public func validate() throws {
        guard startedAt.timeIntervalSince1970.isFinite, startedAt.timeIntervalSince1970 > 0 else {
            throw DomainError.invalidWorkout
        }
    }
}

public struct WorkoutRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let mode: WorkoutMode
    public let startedAt: Date
    public let endedAt: Date
    public let durationMinutes: Int
    public let repetitions: Int?
    public let distanceMeters: Double?
    public let calories: Int?
    public let activity: WorkoutActivity?

    public init(id: UUID, mode: WorkoutMode, startedAt: Date, endedAt: Date, durationMinutes: Int,
                repetitions: Int? = nil, distanceMeters: Double? = nil, calories: Int? = nil,
                activity: WorkoutActivity? = nil) throws {
        self.id = id
        self.mode = mode
        self.startedAt = Date(timeIntervalSince1970: floor(startedAt.timeIntervalSince1970))
        self.endedAt = Date(timeIntervalSince1970: floor(endedAt.timeIntervalSince1970))
        self.durationMinutes = durationMinutes
        self.repetitions = repetitions
        self.distanceMeters = distanceMeters
        self.calories = calories
        self.activity = activity
        try validate()
    }

    public func validate() throws {
        guard startedAt.timeIntervalSince1970.isFinite, startedAt.timeIntervalSince1970 > 0,
              endedAt.timeIntervalSince1970.isFinite, endedAt >= startedAt,
              (1...1_440).contains(durationMinutes) else { throw DomainError.invalidWorkout }
        if let repetitions, !(0...100_000).contains(repetitions) { throw DomainError.invalidWorkout }
        if let distanceMeters, !distanceMeters.isFinite || !(0...200_000).contains(distanceMeters) {
            throw DomainError.invalidWorkout
        }
        if let calories, !(0...10_000).contains(calories) { throw DomainError.invalidWorkout }
    }
}
