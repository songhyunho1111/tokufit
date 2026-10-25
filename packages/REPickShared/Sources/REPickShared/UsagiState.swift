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
    public let kind: MealKind?

    public init(id: UUID = UUID(), name: String, calories: Int, source: MealSource, recordedAt: Date,
                nutrients: MealNutrients? = nil, kind: MealKind? = nil) throws {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.calories = calories
        self.source = source
        // Local logs use whole-second ISO-8601 timestamps for identical save/load values.
        self.recordedAt = Date(timeIntervalSince1970: floor(recordedAt.timeIntervalSince1970))
        self.nutrients = nutrients
        self.kind = kind
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
    public private(set) var attendance = AttendanceProgress()
    public private(set) var freeDraws = 0
    public private(set) var gachaReceipts: [GachaReceipt] = []
    public private(set) var exerciseCaloriesToday = 0
    public private(set) var totalExerciseCalories = 0
    public private(set) var totalStrengthMinutes = 0
    public private(set) var ownedCostumes: [CharacterCostume] = []
    public private(set) var equippedCostumes: [CharacterCostume] = []
    private var dailyNutrition = DailyNutritionProgress()
    private var hasConfiguredCalorieRange = false
    private var dailyMissions = DailyMissionProgress()
    private var missionRewards = MissionRewardProgress()

    public init(now: Date = Date(), calendar: Calendar = .current) {
        daily = DailyProgress(day: Self.dayKey(for: now, calendar: calendar))
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, profile, daily, nextGoalSteps, points, ownedOutfits, equippedOutfit, totalFoodCalories
        case preferences, initialWeightKG, ownedItems, equippedItems, activeWorkout, workouts
        case mealHistory, wellnessHistory
        case attendance, freeDraws, gachaReceipts, exerciseCaloriesToday, totalExerciseCalories, totalStrengthMinutes
        case ownedCostumes, equippedCostumes, dailyNutrition, hasConfiguredCalorieRange, dailyMissions, missionRewards
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
        attendance = values.contains(.attendance) ? try values.decode(AttendanceProgress.self, forKey: .attendance) : AttendanceProgress()
        freeDraws = values.contains(.freeDraws) ? try values.decode(Int.self, forKey: .freeDraws) : 0
        gachaReceipts = values.contains(.gachaReceipts) ? try values.decode([GachaReceipt].self, forKey: .gachaReceipts) : []
        // Legacy migration credits only retained, explicitly recorded data; unknown calories stay unknown.
        try workouts.forEach { try $0.validate() }
        totalExerciseCalories = values.contains(.totalExerciseCalories)
            ? try values.decode(Int.self, forKey: .totalExerciseCalories)
            : try Self.workoutTotal(workouts) { $0.calories ?? 0 }
        totalStrengthMinutes = values.contains(.totalStrengthMinutes)
            ? try values.decode(Int.self, forKey: .totalStrengthMinutes)
            : try Self.workoutTotal(workouts) { $0.activity == .strength ? $0.durationMinutes : 0 }
        exerciseCaloriesToday = values.contains(.exerciseCaloriesToday)
            ? try values.decode(Int.self, forKey: .exerciseCaloriesToday)
            : try Self.workoutTotal(workouts.filter { Self.dayKey(for: $0.endedAt) == daily.day }) { $0.calories ?? 0 }
        ownedCostumes = values.contains(.ownedCostumes) ? try values.decode([CharacterCostume].self, forKey: .ownedCostumes) : []
        equippedCostumes = values.contains(.equippedCostumes) ? try values.decode([CharacterCostume].self, forKey: .equippedCostumes) : []
        dailyNutrition = values.contains(.dailyNutrition)
            ? try values.decode(DailyNutritionProgress.self, forKey: .dailyNutrition)
            : DailyNutritionProgress(minimum: preferences.calorieMinimum, maximum: preferences.calorieMaximum)
        hasConfiguredCalorieRange = values.contains(.hasConfiguredCalorieRange)
            ? try values.decode(Bool.self, forKey: .hasConfiguredCalorieRange) : preferences.calorieMinimum != nil
        dailyMissions = values.contains(.dailyMissions)
            ? try values.decode(DailyMissionProgress.self, forKey: .dailyMissions) : DailyMissionProgress()
        missionRewards = values.contains(.missionRewards)
            ? try values.decode(MissionRewardProgress.self, forKey: .missionRewards) : MissionRewardProgress()
    }

    public var weightChangeKG: Double? {
        guard let initialWeightKG, let profile else { return nil }
        return profile.weightKG - initialWeightKG
    }

    public var workoutMinutesToday: Int {
        workouts.filter { Self.dayKey(for: $0.endedAt) == daily.day }.reduce(0) { $0 + $1.durationMinutes }
    }

    public var recordedWorkoutCount: Int { workouts.count }

    public var hasCheckedInToday: Bool { attendance.lastCheckInDay == daily.day }

    public var attendanceNeedsAttention: Bool {
        guard let last = attendance.lastCheckInDay,
              let elapsedDays = AttendanceProgress.distance(from: last, to: daily.day) else { return false }
        return elapsedDays > 1
    }

    public var attendanceStreak: Int { attendanceNeedsAttention ? 0 : attendance.streak }

    // Cartoon strength progress only; neither this nor energy balance measures body composition.
    public var muscleLevel: Double { min(1, Double(totalStrengthMinutes) / 300) }

    public func watchSnapshot() -> UsagiState {
        var snapshot = self
        snapshot.workouts = []
        snapshot.mealHistory = []
        snapshot.wellnessHistory = []
        snapshot.attendance.days = []
        snapshot.gachaReceipts = []
        return snapshot
    }

    public var currentCostume: CostumeStyle? {
        equippedCostumes.first { $0.character == preferences.character }?.style
    }

    public var dailyCalorieMinimum: Int? { dailyNutrition.minimum }
    public var dailyCalorieMaximum: Int? { dailyNutrition.maximum }
    public var calorieRangeChangesTomorrow: Bool {
        dailyNutrition.minimum != preferences.calorieMinimum || dailyNutrition.maximum != preferences.calorieMaximum
    }
    public var recordedCaloriesToday: Int { daily.meals.reduce(0) { $0 + $1.calories } }

    public var nutritionStatus: NutritionStatus {
        guard let minimum = dailyCalorieMinimum, let maximum = dailyCalorieMaximum else { return .unconfigured }
        guard !daily.meals.isEmpty else { return .unrecorded }
        if recordedCaloriesToday < minimum { return .below }
        return recordedCaloriesToday > maximum ? .above : .within
    }

    public var nutritionMood: NutritionMood {
        switch nutritionStatus {
        case .within: .sparkling
        case .below: .lowEnergy
        case .unconfigured, .unrecorded, .above: .neutral
        }
    }

    // This day's recorded food controls game appearance, without rewriting real weight or gross food history.
    public var bodyScale: Double {
        guard let maximum = dailyCalorieMaximum, maximum > 0, nutritionStatus == .above else { return 1 }
        return 1 + min(0.6, 0.6 * Double(recordedCaloriesToday - maximum) / Double(maximum))
    }

    public var targetBodyScale: Double { 1 }

    public var todayStairSteps: Int { dailyMissions.stairSteps }
    public var foodDayConfirmed: Bool { dailyMissions.foodDayConfirmed }
    public var missionRewardPoints: Int { dailyMissions.rewardPoints }
    public var missionRewardStreak: Int {
        guard let last = missionRewards.lastQualifiedDay,
              let distance = AttendanceProgress.distance(from: last, to: daily.day), distance <= 1 else { return 0 }
        return missionRewards.streak
    }

    public func missionProgress(for kind: DailyMissionKind) -> Int {
        switch kind {
        case .calorieRange: dailyMissions.foodDayConfirmed ? 1 : 0
        case .stairs: min(5, dailyMissions.stairSteps)
        case .threeMeals: Set(daily.meals.compactMap(\.kind).filter { $0 != .snack }).count
        }
    }

    public func missionTarget(for kind: DailyMissionKind) -> Int {
        switch kind {
        case .calorieRange: 1
        case .stairs: 5
        case .threeMeals: 3
        }
    }

    public func missionRewardClaimed(_ kind: DailyMissionKind) -> Bool { dailyMissions.claimed.contains(kind) }

    public mutating func recordStairSteps(_ total: Int, now: Date = Date(), calendar: Calendar = .current) throws {
        try requireProfile()
        guard (0...100_000).contains(total) else { throw MissionError.invalidStairSteps }
        try requireCurrentOrLaterDay(now, calendar: calendar)
        var candidate = self
        candidate.rollover(now: now, calendar: calendar)
        candidate.dailyMissions.stairSteps = max(candidate.dailyMissions.stairSteps, total)
        self = candidate
    }

    public mutating func confirmFoodDay(now: Date = Date(), calendar: Calendar = .current) throws {
        try requireProfile()
        try requireCurrentOrLaterDay(now, calendar: calendar)
        var candidate = self
        candidate.rollover(now: now, calendar: calendar)
        if candidate.dailyMissions.foodDayConfirmed { return }
        guard candidate.nutritionStatus == .within, candidate.missionProgress(for: .threeMeals) == 3 else {
            throw MissionError.foodDayIncomplete
        }
        candidate.dailyMissions.foodDayConfirmed = true
        candidate.dailyMissions.confirmedFoodCalories = candidate.recordedCaloriesToday
        self = candidate
    }

    @discardableResult
    public mutating func claimMission(_ kind: DailyMissionKind, now: Date = Date(), calendar: Calendar = .current) throws -> Int {
        try requireProfile()
        try requireCurrentOrLaterDay(now, calendar: calendar)
        var candidate = self
        candidate.rollover(now: now, calendar: calendar)
        if candidate.missionRewardClaimed(kind) { return 0 }
        guard candidate.hasCheckedInToday else { throw MissionError.checkInRequired }
        guard candidate.missionProgress(for: kind) >= candidate.missionTarget(for: kind) else { throw MissionError.incomplete }
        let reward = candidate.missionRewardPoints
        candidate.points = try Self.addProgress(candidate.points, reward)
        if candidate.missionRewards.lastQualifiedDay != candidate.daily.day {
            let consecutive = candidate.missionRewards.lastQualifiedDay.flatMap {
                AttendanceProgress.distance(from: $0, to: candidate.daily.day)
            } == 1
            candidate.missionRewards.streak = consecutive ? try Self.addProgress(candidate.missionRewards.streak, 1) : 1
            candidate.missionRewards.lastQualifiedDay = candidate.daily.day
        }
        candidate.dailyMissions.claimed.append(kind)
        self = candidate
        return reward
    }

    public mutating func buyCostume(_ item: CharacterCostume) throws {
        try requireProfile()
        guard !ownedCostumes.contains(item) else { throw DomainError.alreadyOwned }
        guard points >= item.price else { throw DomainError.insufficientPoints }
        points -= item.price
        ownedCostumes.append(item)
        equippedCostumes.removeAll { $0.character == item.character }
        equippedCostumes.append(item)
    }

    public mutating func equipCostume(_ item: CharacterCostume) throws {
        try requireProfile()
        guard ownedCostumes.contains(item) else { throw DomainError.invalidOutfit }
        equippedCostumes.removeAll { $0.character == item.character }
        equippedCostumes.append(item)
    }

    public mutating func unequipCostume() {
        equippedCostumes.removeAll { $0.character == preferences.character }
    }

    private func requireCurrentOrLaterDay(_ now: Date, calendar: Calendar) throws {
        let day = Self.dayKey(for: now, calendar: calendar)
        guard Self.isValidDay(day), day >= daily.day else { throw GrowthError.clockMovedBackward }
    }

    public mutating func rollover(now: Date = Date(), calendar: Calendar = .current) {
        let day = Self.dayKey(for: now, calendar: calendar)
        retainHealthHistory(now: now, calendar: calendar)
        // Moving the clock backward must not reopen an already rewarded day.
        guard day > daily.day else { return }
        daily = DailyProgress(day: day, goalSteps: nextGoalSteps ?? daily.goalSteps)
        dailyNutrition = DailyNutritionProgress(minimum: preferences.calorieMinimum, maximum: preferences.calorieMaximum)
        dailyMissions = DailyMissionProgress()
        if let last = missionRewards.lastQualifiedDay, AttendanceProgress.distance(from: last, to: day) == 1 {
            dailyMissions.rewardPoints = (missionRewards.streak + 1) * 5
        }
        exerciseCaloriesToday = 0
        nextGoalSteps = nil
    }

    public mutating func checkIn(now: Date = Date(), calendar: Calendar = .current) throws {
        try requireProfile()
        let day = Self.dayKey(for: now, calendar: calendar)
        guard Self.isValidDay(day), day >= daily.day else { throw GrowthError.clockMovedBackward }
        var candidate = self
        candidate.rollover(now: now, calendar: calendar)
        if candidate.attendance.lastCheckInDay != day {
            let isConsecutive = candidate.attendance.lastCheckInDay.flatMap {
                AttendanceProgress.distance(from: $0, to: day)
            } == 1
            let (streak, overflow) = candidate.attendance.streak.addingReportingOverflow(1)
            guard !overflow else { throw DomainError.invalidSave }
            candidate.attendance.streak = isConsecutive ? streak : 1
            candidate.attendance.lastCheckInDay = day
            candidate.attendance.days.append(day)
            candidate.attendance.days = Array(candidate.attendance.days.suffix(366))
        }
        try candidate.grantAttendanceDrawIfEligible()
        self = candidate
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
        if !hasConfiguredCalorieRange, normalized.calorieMinimum != nil {
            dailyNutrition = DailyNutritionProgress(minimum: normalized.calorieMinimum, maximum: normalized.calorieMaximum)
            hasConfiguredCalorieRange = true
        }
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
    public mutating func startWorkout(mode: WorkoutMode, now: Date = Date(), activity: WorkoutActivity? = nil) throws -> WorkoutSession {
        try requireProfile()
        guard activeWorkout == nil else { throw DomainError.workoutAlreadyActive }
        let session = WorkoutSession(mode: mode, startedAt: now, activity: activity)
        try session.validate()
        activeWorkout = session
        return session
    }

    @discardableResult
    public mutating func finishWorkout(durationMinutes: Int, repetitions: Int? = nil, distanceMeters: Double? = nil,
                                       calories: Int? = nil, now: Date = Date(), sessionID: UUID? = nil,
                                       activity: WorkoutActivity? = nil, calendar: Calendar = .current) throws -> WorkoutRecord {
        if let sessionID, let recorded = workouts.first(where: { $0.id == sessionID }) { return recorded }
        guard let session = activeWorkout, sessionID == nil || sessionID == session.id else {
            throw DomainError.noActiveWorkout
        }
        let selectedActivity = activity ?? session.activity
        let estimatedCalories = selectedActivity.flatMap { activity in
            profile.flatMap { ExerciseEnergy.estimateCalories(activity: activity, minutes: durationMinutes, weightKG: $0.weightKG) }
        }
        let recordedCalories = calories ?? estimatedCalories
        let source: WorkoutCalorieSource? = calories != nil ? .manual : (estimatedCalories != nil ? .estimated : nil)
        let record = try WorkoutRecord(id: session.id, mode: session.mode, startedAt: session.startedAt,
                                       endedAt: now, durationMinutes: durationMinutes, repetitions: repetitions,
                                       distanceMeters: distanceMeters, calories: recordedCalories,
                                       activity: selectedActivity, calorieSource: source)
        var candidate = self
        candidate.rollover(now: now, calendar: calendar)
        candidate.totalExerciseCalories = try Self.addProgress(candidate.totalExerciseCalories, recordedCalories ?? 0)
        if selectedActivity == .strength {
            candidate.totalStrengthMinutes = try Self.addProgress(candidate.totalStrengthMinutes, durationMinutes)
        }
        if Self.dayKey(for: record.endedAt, calendar: calendar) == candidate.daily.day {
            candidate.exerciseCaloriesToday = try Self.addProgress(candidate.exerciseCaloriesToday, recordedCalories ?? 0)
        }
        candidate.workouts.append(record)
        if candidate.workouts.count > 200 { candidate.workouts.removeFirst(candidate.workouts.count - 200) }
        candidate.activeWorkout = nil
        self = candidate
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
        var candidate = self
        candidate.daily.steps = max(candidate.daily.steps, steps)
        try candidate.grantAttendanceDrawIfEligible()
        self = candidate
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
        let outfit = Outfit.drawPool[randomIndex]
        let duplicate = ownedOutfits.contains(outfit)
        try spendGachaPayment(.points, wasDuplicate: duplicate)
        if !duplicate { ownedOutfits.append(outfit) }
        equippedOutfit = outfit
        appendGachaReceipt(GachaReceipt(id: UUID(), outfit: outfit, wasDuplicate: duplicate, payment: .points))
        return outfit
    }

    @discardableResult
    public mutating func openGacha(id: UUID, randomIndex: Int, payment: GachaPayment,
                                   character: CharacterKind? = nil) throws -> GachaReceipt {
        if let receipt = gachaReceipts.first(where: { $0.id == id }) { return receipt }
        try requireProfile()
        guard CostumeStyle.allCases.indices.contains(randomIndex) else { throw DomainError.invalidOutfit }
        let costume = CharacterCostume(character: character ?? preferences.character, style: CostumeStyle.allCases[randomIndex])
        let wasDuplicate = ownedCostumes.contains(costume)
        try spendGachaPayment(payment, wasDuplicate: wasDuplicate)
        if !wasDuplicate { ownedCostumes.append(costume) }
        equippedCostumes.removeAll { $0.character == costume.character }
        equippedCostumes.append(costume)
        let receipt = GachaReceipt(id: id, costume: costume, wasDuplicate: wasDuplicate, payment: payment)
        appendGachaReceipt(receipt)
        return receipt
    }

    private mutating func spendGachaPayment(_ payment: GachaPayment, wasDuplicate: Bool) throws {
        switch payment {
        case .free:
            guard freeDraws > 0 else { throw GrowthError.noFreeDraws }
        case .points:
            guard daily.isGoalComplete else { throw DomainError.goalIncomplete }
            guard daily.draws < daily.maximumDraws else { throw DomainError.dailyDrawLimit }
            guard points >= 100 else { throw DomainError.insufficientPoints }
        }
        let balance = try Self.addProgress(points - (payment == .points ? 100 : 0), wasDuplicate ? 50 : 0)
        points = balance
        if payment == .free { freeDraws -= 1 }
        else { daily.draws += 1 }
    }

    private mutating func appendGachaReceipt(_ receipt: GachaReceipt) {
        gachaReceipts.append(receipt)
        // shortcut: retry receipts retain the latest 200 draws; old receipts require a server ledger for unbounded retries.
        if gachaReceipts.count > 200 { gachaReceipts.removeFirst(gachaReceipts.count - 200) }
    }

    private mutating func grantAttendanceDrawIfEligible() throws {
        guard hasCheckedInToday, attendance.streak > 0, attendance.streak.isMultiple(of: 10),
              daily.isGoalComplete, attendance.lastRewardDay != daily.day else { return }
        freeDraws = try Self.addProgress(freeDraws, 1)
        attendance.lastRewardDay = daily.day
    }

    private static func addProgress(_ current: Int, _ increment: Int) throws -> Int {
        let (value, overflow) = current.addingReportingOverflow(increment)
        guard current >= 0, increment >= 0, !overflow else { throw DomainError.invalidSave }
        return value
    }

    private static func workoutTotal(_ records: [WorkoutRecord], value: (WorkoutRecord) -> Int) throws -> Int {
        try records.reduce(0) { total, record in
            try addProgress(total, value(record))
        }
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
                                 nutrients: MealNutrients? = nil, id: UUID = UUID(), kind: MealKind? = nil,
                                 calendar: Calendar = .current) throws {
        try requireProfile()
        let meal = try MealEntry(id: id, name: name, calories: calories, source: source, recordedAt: now, nutrients: nutrients, kind: kind)
        // shortcut: deduplication follows meal retention; add receipts if retryable drafts outlive retained records.
        if let existing = daily.meals.first(where: { $0.id == id }) ?? mealHistory.first(where: { $0.id == id }) {
            // Retries preserve the original timestamp even when the save is attempted later.
            guard existing.name == meal.name, existing.calories == meal.calories,
                  existing.source == meal.source, existing.nutrients == meal.nutrients,
                  existing.kind == meal.kind else { throw DomainError.invalidMeal }
            return
        }
        let (total, overflow) = totalFoodCalories.addingReportingOverflow(calories)
        guard !overflow else { throw DomainError.invalidMeal }
        var candidate = self
        candidate.rollover(now: now, calendar: calendar)
        if Self.dayKey(for: now, calendar: calendar) == candidate.daily.day {
            candidate.daily.meals.append(meal)
        } else {
            candidate.mealHistory.append(meal)
        }
        candidate.totalFoodCalories = total
        candidate.retainHealthHistory(now: now, calendar: calendar)
        self = candidate
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
        try attendance.validate(currentDay: daily.day)
        try dailyNutrition.validate()
        try dailyMissions.validate()
        try missionRewards.validate(currentDay: daily.day)
        let expectedMissionReward: Int
        if missionRewards.lastQualifiedDay == daily.day {
            expectedMissionReward = missionRewards.streak * 5
        } else if let last = missionRewards.lastQualifiedDay, AttendanceProgress.distance(from: last, to: daily.day) == 1 {
            expectedMissionReward = (missionRewards.streak + 1) * 5
        } else {
            expectedMissionReward = 5
        }
        if dailyMissions.foodDayConfirmed {
            guard let calories = dailyMissions.confirmedFoodCalories,
                  let minimum = dailyCalorieMinimum, let maximum = dailyCalorieMaximum,
                  (minimum...maximum).contains(calories), calories <= recordedCaloriesToday else {
                throw DomainError.invalidSave
            }
        } else if dailyMissions.confirmedFoodCalories != nil {
            throw DomainError.invalidSave
        }
        guard hasConfiguredCalorieRange || (dailyNutrition.minimum == nil && preferences.calorieMinimum == nil),
              dailyMissions.rewardPoints == expectedMissionReward,
              Set(ownedCostumes).count == ownedCostumes.count,
              equippedCostumes.allSatisfy(ownedCostumes.contains),
              Set(equippedCostumes.map(\.character)).count == equippedCostumes.count,
              !dailyMissions.foodDayConfirmed || (dailyCalorieMinimum != nil && missionProgress(for: .threeMeals) == 3),
              dailyMissions.claimed.allSatisfy({ missionProgress(for: $0) >= missionTarget(for: $0) }),
              dailyMissions.claimed.isEmpty || (hasCheckedInToday && missionRewards.lastQualifiedDay == daily.day),
              missionRewards.lastQualifiedDay != daily.day || !dailyMissions.claimed.isEmpty else {
            throw DomainError.invalidSave
        }
        guard freeDraws >= 0, gachaReceipts.count <= 200,
              Set(gachaReceipts.map(\.id)).count == gachaReceipts.count,
              gachaReceipts.allSatisfy({ receipt in
                  switch (receipt.outfit, receipt.costume) {
                  case let (.some(outfit), nil): Outfit.drawPool.contains(outfit) && ownedOutfits.contains(outfit)
                  case let (nil, .some(costume)): ownedCostumes.contains(costume)
                  default: false
                  }
              }),
              exerciseCaloriesToday >= 0, exerciseCaloriesToday <= totalExerciseCalories,
              totalExerciseCalories >= 0, totalStrengthMinutes >= 0 else { throw DomainError.invalidSave }
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
        guard totalExerciseCalories >= (try Self.workoutTotal(workouts) { $0.calories ?? 0 }),
              totalStrengthMinutes >= (try Self.workoutTotal(workouts) { $0.activity == .strength ? $0.durationMinutes : 0 }) else {
            throw DomainError.invalidSave
        }
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
                  attendance == AttendanceProgress(), freeDraws == 0, gachaReceipts.isEmpty,
                  ownedCostumes.isEmpty, equippedCostumes.isEmpty, dailyMissions == DailyMissionProgress(),
                  missionRewards == MissionRewardProgress(), !hasConfiguredCalorieRange,
                  totalExerciseCalories == 0, totalStrengthMinutes == 0,
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
