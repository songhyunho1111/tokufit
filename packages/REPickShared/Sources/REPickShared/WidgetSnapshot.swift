import Foundation

public enum WidgetStorage {
    public static let appGroup = "group.dev.repick.shared"
    public static let filename = "usagi-widget-v1.json"
    public static let kind = "REPickUsagiWidget"
    public static let watchKind = "REPickUsagiComplication"
    public static let maximumPayloadBytes = 3_000_000
}

public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public let version: Int
    public let hasProfile: Bool
    public let bodyScale: Double
    public let outfit: Outfit
    public let day: String
    public let steps: Int
    public let goalSteps: Int
    public let waterML: Int
    public let points: Int
    public let updatedAt: Date
    public let name: String
    public let character: CharacterKind
    public let equippedItems: [WardrobeItem]
    public let activeWorkoutMode: WorkoutMode?

    public init(state: UsagiState, now: Date = Date()) {
        version = 1
        hasProfile = state.profile != nil
        bodyScale = state.bodyScale
        outfit = state.equippedOutfit
        day = state.daily.day
        steps = state.daily.steps
        goalSteps = state.daily.goalSteps
        waterML = state.daily.waterML
        points = state.points
        updatedAt = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970))
        name = state.preferences.name
        character = state.preferences.character
        equippedItems = state.equippedItems
        activeWorkoutMode = state.activeWorkout?.mode
    }

    private enum CodingKeys: String, CodingKey {
        case version, hasProfile, bodyScale, outfit, day, steps, goalSteps, waterML, points, updatedAt
        case name, character, equippedItems, activeWorkoutMode
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        hasProfile = try values.decode(Bool.self, forKey: .hasProfile)
        bodyScale = try values.decode(Double.self, forKey: .bodyScale)
        outfit = try values.decode(Outfit.self, forKey: .outfit)
        day = try values.decode(String.self, forKey: .day)
        steps = try values.decode(Int.self, forKey: .steps)
        goalSteps = try values.decode(Int.self, forKey: .goalSteps)
        waterML = try values.decode(Int.self, forKey: .waterML)
        points = try values.decode(Int.self, forKey: .points)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
        name = values.contains(.name) ? try values.decode(String.self, forKey: .name) : "우사기"
        character = values.contains(.character) ? try values.decode(CharacterKind.self, forKey: .character) : .usagi
        equippedItems = values.contains(.equippedItems) ? try values.decode([WardrobeItem].self, forKey: .equippedItems) : []
        activeWorkoutMode = try values.decodeIfPresent(WorkoutMode.self, forKey: .activeWorkoutMode)
    }

    public func validate() throws {
        guard version == 1, bodyScale.isFinite, (0.75...1.6).contains(bodyScale),
              UsagiState.isValidDay(day), (0...200_000).contains(steps),
              (2_000...10_000).contains(goalSteps), goalSteps.isMultiple(of: 1_000),
              (0...10_000).contains(waterML), points >= 0,
              updatedAt.timeIntervalSince1970.isFinite, updatedAt.timeIntervalSince1970 > 0,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 24,
              !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              Set(equippedItems.map(\.category)).count == equippedItems.count else {
            throw WidgetPayloadError.invalidSnapshot
        }
    }

    public func isStale(at date: Date = Date(), calendar: Calendar = .current) -> Bool {
        day != UsagiState.dayKey(for: date, calendar: calendar)
            || date.timeIntervalSince(updatedAt) > 15 * 60
            || updatedAt.timeIntervalSince(date) > 5 * 60
    }
}

public struct WidgetPayload: Codable, Sendable {
    public let snapshot: WidgetSnapshot
    public let characterPNG: Data?

    public init(snapshot: WidgetSnapshot, characterPNG: Data?) throws {
        self.snapshot = snapshot
        self.characterPNG = characterPNG
        try validate()
    }

    public func validate() throws {
        try snapshot.validate()
        if let characterPNG {
            let signature = Data([137, 80, 78, 71, 13, 10, 26, 10])
            guard characterPNG.count <= 2_000_000, characterPNG.starts(with: signature) else {
                throw WidgetPayloadError.invalidImage
            }
        }
    }
}

public enum WidgetPayloadError: Error {
    case invalidSnapshot, invalidImage
}
