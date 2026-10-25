import Foundation

public enum Outfit: String, Codable, CaseIterable, Sendable, Identifiable {
    case basic, student, office, sport

    public var id: String { rawValue }
    public var price: Int { self == .basic ? 0 : 500 }
    public static let drawPool: [Outfit] = [.student, .office, .sport]

    public var name: String {
        switch self {
        case .basic: String(localized: "outfit.basic", bundle: .module)
        case .student: String(localized: "outfit.student", bundle: .module)
        case .office: String(localized: "outfit.office", bundle: .module)
        case .sport: String(localized: "outfit.sport", bundle: .module)
        }
    }
}

public enum MealSource: String, Codable, Sendable {
    case manual, onDeviceAI, photoAI
}

public enum ProfileGender: String, Codable, CaseIterable, Sendable, Identifiable {
    case male, female, notSpecified

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .male: String(localized: "gender.male", bundle: .module)
        case .female: String(localized: "gender.female", bundle: .module)
        case .notSpecified: String(localized: "gender.notSpecified", bundle: .module)
        }
    }
}

public struct UserProfile: Codable, Sendable, Equatable {
    public private(set) var heightCM: Double
    public private(set) var weightKG: Double
    public private(set) var targetWeightKG: Double
    public private(set) var gender: ProfileGender?

    public var bmi: Double { weightKG / pow(heightCM / 100, 2) }
    public var targetBMI: Double { targetWeightKG / pow(heightCM / 100, 2) }

    public init(heightCM: Double, weightKG: Double, targetWeightKG: Double, gender: ProfileGender? = nil) throws {
        self.heightCM = heightCM
        self.weightKG = weightKG
        self.targetWeightKG = targetWeightKG
        self.gender = gender
        try validate()
    }

    func validate() throws {
        guard heightCM.isFinite, weightKG.isFinite, targetWeightKG.isFinite,
              (80...250).contains(heightCM), (20...350).contains(weightKG),
              (20...350).contains(targetWeightKG) else { throw DomainError.invalidProfile }
    }
}

public struct MealEntry: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let calories: Int
    public let source: MealSource
    public let recordedAt: Date
    public let nutrients: MealNutrients?

    public init(id: UUID = UUID(), name: String, calories: Int, source: MealSource, recordedAt: Date,
                nutrients: MealNutrients? = nil) throws {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.calories = calories
        self.source = source
        // Local logs use whole-second ISO-8601 timestamps for identical save/load values.
        self.recordedAt = Date(timeIntervalSince1970: floor(recordedAt.timeIntervalSince1970))
        self.nutrients = nutrients
        try validate()
    }

    func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.count <= 120, (1...5_000).contains(calories),
              source != .photoAI || nutrients != nil,
              recordedAt.timeIntervalSince1970.isFinite else { throw DomainError.invalidMeal }
        try nutrients?.validate()
    }
}

public struct DailyProgress: Codable, Sendable, Equatable {
    public internal(set) var day: String
    public internal(set) var goalSteps: Int
    public internal(set) var steps: Int = 0
    public internal(set) var rewardClaimed = false
    public internal(set) var draws = 0
    public internal(set) var waterML = 0
    public internal(set) var meals: [MealEntry] = []

    public var maximumDraws: Int { min(5, max(1, goalSteps / 2_000)) }
    public var goalReward: Int { goalSteps / 1_000 * 50 }
    public var isGoalComplete: Bool { steps >= goalSteps }

    init(day: String, goalSteps: Int = 6_000) {
        self.day = day
        self.goalSteps = goalSteps
    }

    func validate() throws {
        try UsagiState.validateGoal(goalSteps)
        guard UsagiState.isValidDay(day), (0...200_000).contains(steps),
              (0...maximumDraws).contains(draws), (0...10_000).contains(waterML),
              (!rewardClaimed && draws == 0) || isGoalComplete,
              Set(meals.map(\.id)).count == meals.count else { throw DomainError.invalidSave }
        try meals.forEach { try $0.validate() }
    }
}

public struct UsagiState: Codable, Sendable, Equatable {
    public private(set) var schemaVersion = 1
    public private(set) var profile: UserProfile?
    public private(set) var daily: DailyProgress
    public private(set) var nextGoalSteps: Int?
    public private(set) var points = 0
    public private(set) var ownedOutfits: [Outfit] = [.basic]
    public private(set) var equippedOutfit: Outfit = .basic
    public private(set) var totalFoodCalories = 0
    public private(set) var preferences = CompanionPreferences()
    public private(set) var initialWeightKG: Double?
    public private(set) var ownedItems: [WardrobeItem] = []
    public private(set) var equippedItems: [WardrobeItem] = []
    public private(set) var activeWorkout: WorkoutSession?
    public private(set) var workouts: [WorkoutRecord] = []
    public private(set) var mealHistory: [MealEntry] = []
    public private(set) var wellnessHistory: [WellnessEntry] = []

    public init(now: Date = Date(), calendar: Calendar = .current) {
        daily = DailyProgress(day: Self.dayKey(for: now, calendar: calendar))
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, profile, daily, nextGoalSteps, points, ownedOutfits, equippedOutfit, totalFoodCalories
        case preferences, initialWeightKG, ownedItems, equippedItems, activeWorkout, workouts
        case mealHistory, wellnessHistory
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        profile = try values.decodeIfPresent(UserProfile.self, forKey: .profile)
        daily = try values.decode(DailyProgress.self, forKey: .daily)
        nextGoalSteps = try values.decodeIfPresent(Int.self, forKey: .nextGoalSteps)
        points = try values.decode(Int.self, forKey: .points)
        ownedOutfits = try values.decode([Outfit].self, forKey: .ownedOutfits)
        equippedOutfit = try values.decode(Outfit.self, forKey: .equippedOutfit)
        totalFoodCalories = try values.decode(Int.self, forKey: .totalFoodCalories)
        preferences = values.contains(.preferences) ? try values.decode(CompanionPreferences.self, forKey: .preferences) : CompanionPreferences()
        initialWeightKG = try values.decodeIfPresent(Double.self, forKey: .initialWeightKG)
        ownedItems = values.contains(.ownedItems) ? try values.decode([WardrobeItem].self, forKey: .ownedItems) : []
        equippedItems = values.contains(.equippedItems) ? try values.decode([WardrobeItem].self, forKey: .equippedItems) : []
        activeWorkout = try values.decodeIfPresent(WorkoutSession.self, forKey: .activeWorkout)
        workouts = values.contains(.workouts) ? try values.decode([WorkoutRecord].self, forKey: .workouts) : []
        // Only legacy saves need migration; an explicitly empty history is a valid Watch projection.
        mealHistory = values.contains(.mealHistory)
            ? try values.decode([MealEntry].self, forKey: .mealHistory)
            : Array(daily.meals.sorted(by: Self.mealOrder).suffix(5_000))
        wellnessHistory = values.contains(.wellnessHistory) ? try values.decode([WellnessEntry].self, forKey: .wellnessHistory) : []
    }

    public var weightChangeKG: Double? {
        guard let initialWeightKG, let profile else { return nil }
        return profile.weightKG - initialWeightKG
    }

    public var workoutMinutesToday: Int {
        workouts.filter { Self.dayKey(for: $0.endedAt) == daily.day }.reduce(0) { $0 + $1.durationMinutes }
    }

    public var recordedWorkoutCount: Int { workouts.count }

    public func watchSnapshot() -> UsagiState {
        var snapshot = self
        snapshot.workouts = []
        snapshot.mealHistory = []
        snapshot.wellnessHistory = []
        return snapshot
    }

    // shortcut: food changes a bounded cartoon belly, replace with a balanced game model when nutrition rules are specified.
    public var bodyScale: Double {
        min(1.6, Self.shapeScale(bmi: profile?.bmi ?? 22) + min(0.22, Double(totalFoodCalories) / 40_000))
    }

    public var targetBodyScale: Double { Self.shapeScale(bmi: profile?.targetBMI ?? 22) }

    public mutating func rollover(now: Date = Date(), calendar: Calendar = .current) {
        let day = Self.dayKey(for: now, calendar: calendar)
        retainHealthHistory(now: now, calendar: calendar)
        // Moving the clock backward must not reopen an already rewarded day.
        guard day > daily.day else { return }
        daily = DailyProgress(day: day, goalSteps: nextGoalSteps ?? daily.goalSteps)
        nextGoalSteps = nil
    }

    public mutating func setProfile(heightCM: Double, weightKG: Double, targetWeightKG: Double, goalSteps: Int, gender: ProfileGender? = nil) throws {
        let profile = try UserProfile(heightCM: heightCM, weightKG: weightKG, targetWeightKG: targetWeightKG, gender: gender ?? self.profile?.gender)
        try Self.validateGoal(goalSteps)
        // Legacy saves have no historical baseline; the first explicit edit establishes one.
        if initialWeightKG == nil { initialWeightKG = self.profile?.weightKG ?? profile.weightKG }
        if self.profile == nil {
            daily.goalSteps = goalSteps
        } else {
            nextGoalSteps = goalSteps == daily.goalSteps ? nil : goalSteps
        }
        self.profile = profile
    }

    public mutating func setPreferences(_ preferences: CompanionPreferences) throws {
        try requireProfile()
        var normalized = preferences
        normalized.name = normalized.name.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.goalTitle = normalized.goalTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        try normalized.validate()
        self.preferences = normalized
    }

    public mutating func buyItem(_ item: WardrobeItem) throws {
        try requireProfile()
        guard !ownedItems.contains(item) else { throw DomainError.alreadyOwned }
        guard points >= item.price else { throw DomainError.insufficientPoints }
        points -= item.price
        ownedItems.append(item)
        equippedItems.removeAll { $0.category == item.category }
        equippedItems.append(item)
    }

    public mutating func equipItem(_ item: WardrobeItem) throws {
        try requireProfile()
        guard ownedItems.contains(item) else { throw DomainError.invalidOutfit }
        equippedItems.removeAll { $0.category == item.category }
        equippedItems.append(item)
    }

    public mutating func unequipItem(in category: WardrobeCategory) {
        if category == .top { equippedOutfit = .basic }
        equippedItems.removeAll { $0.category == category }
    }

    @discardableResult
    public mutating func startWorkout(mode: WorkoutMode, now: Date = Date()) throws -> WorkoutSession {
        try requireProfile()
        guard activeWorkout == nil else { throw DomainError.workoutAlreadyActive }
        let session = WorkoutSession(mode: mode, startedAt: now)
        try session.validate()
        activeWorkout = session
        return session
    }

    @discardableResult
    public mutating func finishWorkout(durationMinutes: Int, repetitions: Int? = nil, distanceMeters: Double? = nil,
                                       calories: Int? = nil, now: Date = Date(), sessionID: UUID? = nil,
                                       activity: WorkoutActivity? = nil) throws -> WorkoutRecord {
        if let sessionID, let recorded = workouts.first(where: { $0.id == sessionID }) { return recorded }
        guard let session = activeWorkout, sessionID == nil || sessionID == session.id else {
            throw DomainError.noActiveWorkout
        }
        let record = try WorkoutRecord(id: session.id, mode: session.mode, startedAt: session.startedAt,
                                       endedAt: now, durationMinutes: durationMinutes, repetitions: repetitions,
                                       distanceMeters: distanceMeters, calories: calories, activity: activity)
        workouts.append(record)
        if workouts.count > 200 { workouts.removeFirst(workouts.count - 200) }
        activeWorkout = nil
        return record
    }

    public mutating func cancelWorkout() { activeWorkout = nil }

    public mutating func setNextGoal(_ goal: Int) throws {
        try requireProfile()
        try Self.validateGoal(goal)
        nextGoalSteps = goal == daily.goalSteps ? nil : goal
    }

    public mutating func recordSteps(_ steps: Int) throws {
        guard (0...200_000).contains(steps) else { throw DomainError.invalidSteps }
        daily.steps = max(daily.steps, steps)
    }

    public mutating func claimReward() throws {
        try requireProfile()
        guard daily.isGoalComplete else { throw DomainError.goalIncomplete }
        guard !daily.rewardClaimed else { throw DomainError.rewardAlreadyClaimed }
        let (balance, overflow) = points.addingReportingOverflow(daily.goalReward)
        guard !overflow else { throw DomainError.invalidSave }
        points = balance
        daily.rewardClaimed = true
    }

    @discardableResult
    public mutating func drawOutfit(randomIndex: Int) throws -> Outfit {
        try requireProfile()
        guard Outfit.drawPool.indices.contains(randomIndex) else { throw DomainError.invalidOutfit }
        guard daily.isGoalComplete else { throw DomainError.goalIncomplete }
        guard daily.draws < daily.maximumDraws else { throw DomainError.dailyDrawLimit }
        guard points >= 100 else { throw DomainError.insufficientPoints }
        let outfit = Outfit.drawPool[randomIndex]
        points -= 100
        daily.draws += 1
        if ownedOutfits.contains(outfit) {
            points += 50
        } else {
            ownedOutfits.append(outfit)
        }
        equippedOutfit = outfit
        return outfit
    }

    public mutating func buyOutfit(_ outfit: Outfit) throws {
        try requireProfile()
        guard !ownedOutfits.contains(outfit) else { throw DomainError.alreadyOwned }
        guard points >= outfit.price else { throw DomainError.insufficientPoints }
        points -= outfit.price
        ownedOutfits.append(outfit)
        equippedOutfit = outfit
    }

    public mutating func equip(_ outfit: Outfit) throws {
        guard ownedOutfits.contains(outfit) else { throw DomainError.invalidOutfit }
        equippedOutfit = outfit
    }

    public mutating func addMeal(name: String, calories: Int, source: MealSource, now: Date = Date(),
                                 nutrients: MealNutrients? = nil, id: UUID = UUID()) throws {
        try requireProfile()
        let meal = try MealEntry(id: id, name: name, calories: calories, source: source, recordedAt: now, nutrients: nutrients)
        // shortcut: deduplication follows meal retention; add receipts if retryable drafts outlive retained records.
        if let existing = daily.meals.first(where: { $0.id == id }) ?? mealHistory.first(where: { $0.id == id }) {
            // Retries preserve the original timestamp even when the save is attempted later.
            guard existing.name == meal.name, existing.calories == meal.calories,
                  existing.source == meal.source, existing.nutrients == meal.nutrients else { throw DomainError.invalidMeal }
            return
        }
        let (total, overflow) = totalFoodCalories.addingReportingOverflow(calories)
        guard !overflow else { throw DomainError.invalidMeal }
        daily.meals.append(meal)
        totalFoodCalories = total
        retainHealthHistory(now: now, calendar: .current)
    }

    public mutating func recordWellness(day: String, sleepMinutes: Int? = nil, condition: Int? = nil,
                                        now: Date = Date(), calendar: Calendar = .current) throws {
        try requireProfile()
        let entry = try WellnessEntry(day: day, sleepMinutes: sleepMinutes, condition: condition)
        let today = Self.dayKey(for: now, calendar: calendar)
        guard let oldest = calendar.date(byAdding: .day, value: -365, to: now),
              day <= today, day >= Self.dayKey(for: oldest, calendar: calendar) else {
            throw DomainError.invalidWellness
        }
        wellnessHistory.removeAll { $0.day == day }
        wellnessHistory.append(entry)
        retainHealthHistory(now: now, calendar: calendar)
    }

    public mutating func addWater(_ amount: Int) throws {
        try requireProfile()
        guard (1...2_000).contains(amount), daily.waterML <= 10_000 - amount else {
            throw DomainError.invalidWater
        }
        daily.waterML += amount
    }

    public func validate() throws {
        guard schemaVersion == 1 else { throw DomainError.unsupportedVersion }
        try profile?.validate()
        try daily.validate()
        try preferences.validate()
        guard mealHistory.count <= 5_000, Set(mealHistory.map(\.id)).count == mealHistory.count,
              wellnessHistory.count <= 366, Set(wellnessHistory.map(\.day)).count == wellnessHistory.count else {
            throw DomainError.invalidSave
        }
        try mealHistory.forEach { try $0.validate() }
        try wellnessHistory.forEach { try $0.validate() }
        let historicalMeals = Dictionary(uniqueKeysWithValues: mealHistory.map { ($0.id, $0) })
        guard daily.meals.allSatisfy({ meal in
            historicalMeals[meal.id].map { $0 == meal } ?? true
        }), totalFoodCalories >= mealHistory.reduce(0, { $0 + $1.calories }) else { throw DomainError.invalidSave }
        if let initialWeightKG {
            guard initialWeightKG.isFinite, (20...350).contains(initialWeightKG), profile != nil else {
                throw DomainError.invalidSave
            }
        }
        guard Set(ownedItems).count == ownedItems.count,
              equippedItems.allSatisfy(ownedItems.contains),
              Set(equippedItems.map(\.category)).count == equippedItems.count,
              workouts.count <= 200, Set(workouts.map(\.id)).count == workouts.count else { throw DomainError.invalidSave }
        try workouts.forEach { try $0.validate() }
        if let activeWorkout {
            try activeWorkout.validate()
            guard !workouts.contains(where: { $0.id == activeWorkout.id }) else { throw DomainError.invalidSave }
        }
        if let nextGoalSteps { try Self.validateGoal(nextGoalSteps) }
        guard points >= 0, totalFoodCalories >= 0,
              !ownedOutfits.isEmpty, ownedOutfits.contains(.basic), ownedOutfits.contains(equippedOutfit),
              Set(ownedOutfits).count == ownedOutfits.count else { throw DomainError.invalidSave }
        var dailyCalories = 0
        for meal in daily.meals {
            let (total, overflow) = dailyCalories.addingReportingOverflow(meal.calories)
            guard !overflow else { throw DomainError.invalidSave }
            dailyCalories = total
        }
        guard totalFoodCalories >= dailyCalories else { throw DomainError.invalidSave }
        if profile == nil {
            guard points == 0, !daily.rewardClaimed, daily.draws == 0, daily.meals.isEmpty,
                  daily.waterML == 0, totalFoodCalories == 0, ownedOutfits == [.basic],
                  nextGoalSteps == nil, ownedItems.isEmpty, equippedItems.isEmpty,
                  activeWorkout == nil, workouts.isEmpty, mealHistory.isEmpty, wellnessHistory.isEmpty else { throw DomainError.invalidSave }
        }
    }

    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let values = gregorian.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", values.year ?? 0, values.month ?? 0, values.day ?? 0)
    }

    static func validateGoal(_ goal: Int) throws {
        guard (2_000...10_000).contains(goal), goal.isMultiple(of: 1_000) else { throw DomainError.invalidGoal }
    }

    static func isValidDay(_ day: String) -> Bool {
        let parts = day.split(separator: "-")
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let number = Int(parts[2]),
              (1...9_999).contains(year), (1...12).contains(month), (1...31).contains(number) else { return false }
        let calendar = Calendar(identifier: .gregorian)
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: number)) else { return false }
        return dayKey(for: date, calendar: calendar) == day
    }

    private static func shapeScale(bmi: Double) -> Double {
        min(1.4, max(0.75, 0.9 + (bmi - 18) * 0.025))
    }

    private func requireProfile() throws {
        guard profile != nil else { throw DomainError.profileRequired }
    }

    private static func mealOrder(_ left: MealEntry, _ right: MealEntry) -> Bool {
        left.recordedAt == right.recordedAt ? left.id.uuidString < right.id.uuidString : left.recordedAt < right.recordedAt
    }

    private mutating func retainHealthHistory(now: Date, calendar: Calendar) {
        guard let oldest = calendar.date(byAdding: .day, value: -365, to: now) else { return }
        let cutoff = Self.dayKey(for: oldest, calendar: calendar)
        var meals = Dictionary(mealHistory.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for meal in daily.meals { meals[meal.id] = meal }
        mealHistory = Array(meals.values.filter { Self.dayKey(for: $0.recordedAt, calendar: calendar) >= cutoff }
            .sorted(by: Self.mealOrder).suffix(5_000))
        wellnessHistory = Array(wellnessHistory.filter { $0.day >= cutoff }.sorted { $0.day < $1.day }.suffix(366))
    }
}
