import Foundation

public enum HealthReportPeriod: String, Codable, CaseIterable, Identifiable, Sendable {
    case week, month
    public var id: String { rawValue }
    public var name: String { self == .week ? String(localized: "주간") : String(localized: "월간") }

    public func window(containing anchorDate: String, timeZone: TimeZone = .current,
                       now: Date = Date()) throws -> HealthReportWindow {
        guard HealthReportDates.isSupported(timeZone), now.timeIntervalSince1970.isFinite,
              let anchor = HealthReportDates.parseDay(anchorDate) else { throw HealthReportError.invalidPeriod }
        var local = Calendar(identifier: .gregorian)
        local.timeZone = timeZone
        let todayKey = UsagiState.dayKey(for: now, calendar: local)
        guard let today = HealthReportDates.parseDay(todayKey),
              let age = HealthReportDates.calendar.dateComponents([.day], from: anchor, to: today).day,
              (0...366).contains(age) else { throw HealthReportError.invalidPeriod }
        let calendar = HealthReportDates.calendar
        let start: Date
        let end: Date
        switch self {
        case .week:
            let offset = (calendar.component(.weekday, from: anchor) + 5) % 7
            guard let first = calendar.date(byAdding: .day, value: -offset, to: anchor),
                  let last = calendar.date(byAdding: .day, value: 6, to: first) else { throw HealthReportError.invalidPeriod }
            start = first; end = last
        case .month:
            let components = calendar.dateComponents([.year, .month], from: anchor)
            guard let first = calendar.date(from: components),
                  let next = calendar.date(byAdding: .month, value: 1, to: first),
                  let last = calendar.date(byAdding: .day, value: -1, to: next) else { throw HealthReportError.invalidPeriod }
            start = first; end = last
        }
        let observed = min(end, today)
        guard let days = calendar.dateComponents([.day], from: start, to: end).day,
              let elapsed = calendar.dateComponents([.day], from: start, to: observed).day else { throw HealthReportError.invalidPeriod }
        return HealthReportWindow(startDate: UsagiState.dayKey(for: start, calendar: calendar),
                                  endDate: UsagiState.dayKey(for: end, calendar: calendar),
                                  observedThroughDate: UsagiState.dayKey(for: observed, calendar: calendar),
                                  dayCount: days + 1, elapsedDays: elapsed + 1, timeZone: timeZone.identifier)
    }
}

public struct HealthReportWindow: Codable, Equatable, Sendable {
    public let startDate: String
    public let endDate: String
    public let observedThroughDate: String
    public let dayCount: Int
    public let elapsedDays: Int
    public let timeZone: String

    public init(startDate: String, endDate: String, observedThroughDate: String,
                dayCount: Int, elapsedDays: Int, timeZone: String) {
        self.startDate = startDate; self.endDate = endDate; self.observedThroughDate = observedThroughDate
        self.dayCount = dayCount; self.elapsedDays = elapsedDays; self.timeZone = timeZone
    }

    public func contains(day: String) -> Bool { day >= startDate && day <= observedThroughDate }

    public func validate() throws {
        guard let zone = TimeZone(identifier: timeZone), HealthReportDates.isSupported(zone), timeZone.count <= 80,
              let start = HealthReportDates.parseDay(startDate), let end = HealthReportDates.parseDay(endDate),
              let observed = HealthReportDates.parseDay(observedThroughDate),
              start <= observed, observed <= end, (7...31).contains(dayCount), (1...dayCount).contains(elapsedDays),
              HealthReportDates.calendar.dateComponents([.day], from: start, to: end).day == dayCount - 1,
              HealthReportDates.calendar.dateComponents([.day], from: start, to: observed).day == elapsedDays - 1 else {
            throw HealthReportError.invalidResponse
        }
    }
}

public struct HealthReportRequest: Codable, Equatable, Sendable {
    public let period: HealthReportPeriod
    public let anchorDate: String
    public let timeZone: String
    public let goals: Goals
    public let data: Records
    public var hasRecords: Bool { !data.meals.isEmpty || !data.workouts.isEmpty || !data.wellness.isEmpty }

    public init(period: HealthReportPeriod, anchorDate: String, timeZone: String, goals: Goals, data: Records) {
        self.period = period; self.anchorDate = anchorDate; self.timeZone = timeZone; self.goals = goals; self.data = data
    }

    public static func make(state: UsagiState, period: HealthReportPeriod, anchorDate: String,
                            timeZone: TimeZone = .current, now: Date = Date()) throws -> HealthReportRequest {
        try state.validate()
        guard state.profile != nil else { throw DomainError.profileRequired }
        let window = try period.window(containing: anchorDate, timeZone: timeZone, now: now)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var mealsByID: [UUID: MealEntry] = [:]
        for meal in state.mealHistory + state.daily.meals {
            if let existing = mealsByID[meal.id], existing != meal { throw HealthReportError.invalidRecords }
            mealsByID[meal.id] = meal
        }
        let meals = mealsByID.values.filter {
            $0.recordedAt <= now && window.contains(day: UsagiState.dayKey(for: $0.recordedAt, calendar: calendar))
        }.sorted { $0.recordedAt == $1.recordedAt ? $0.id.uuidString < $1.id.uuidString : $0.recordedAt < $1.recordedAt }
        let workouts = state.workouts.filter {
            $0.endedAt <= now && window.contains(day: UsagiState.dayKey(for: $0.endedAt, calendar: calendar))
        }.sorted { $0.endedAt == $1.endedAt ? $0.id.uuidString < $1.id.uuidString : $0.endedAt < $1.endedAt }
        let wellness = state.wellnessHistory.filter { window.contains(day: $0.day) }.sorted { $0.day < $1.day }
        guard meals.count <= 1_000, workouts.count <= 200, wellness.count <= 31 else { throw HealthReportError.tooManyRecords }
        let request = HealthReportRequest(
            period: period, anchorDate: anchorDate, timeZone: timeZone.identifier,
            goals: Goals(steps: state.daily.goalSteps, calorieMinimum: state.preferences.calorieMinimum,
                         calorieMaximum: state.preferences.calorieMaximum),
            data: Records(meals: meals.map(Meal.init), workouts: workouts.map(Workout.init), wellness: wellness.map(Wellness.init))
        )
        guard try HealthReportCoding.encoder().encode(request).count <= 262_144 else { throw HealthReportError.requestTooLarge }
        return request
    }

    public struct Goals: Codable, Equatable, Sendable {
        public let steps: Int
        public let calorieMinimum: Int?
        public let calorieMaximum: Int?
        public init(steps: Int, calorieMinimum: Int?, calorieMaximum: Int?) {
            self.steps = steps; self.calorieMinimum = calorieMinimum; self.calorieMaximum = calorieMaximum
        }
        private enum CodingKeys: String, CodingKey { case steps, calorieMinimum, calorieMaximum }
        public func encode(to encoder: any Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(steps, forKey: .steps)
            try values.encode(calorieMinimum, forKey: .calorieMinimum)
            try values.encode(calorieMaximum, forKey: .calorieMaximum)
        }
    }

    public struct Records: Codable, Equatable, Sendable {
        public let meals: [Meal]
        public let workouts: [Workout]
        public let wellness: [Wellness]
        public init(meals: [Meal], workouts: [Workout], wellness: [Wellness]) {
            self.meals = meals; self.workouts = workouts; self.wellness = wellness
        }
    }

    public struct Meal: Codable, Equatable, Sendable {
        public let id: UUID
        public let recordedAt: Date
        public let calories: Int
        public let nutrients: MealNutrients?
        public init(_ meal: MealEntry) {
            id = meal.id; recordedAt = meal.recordedAt; calories = meal.calories; nutrients = meal.nutrients
        }
        private enum CodingKeys: String, CodingKey { case id, recordedAt, calories, nutrients }
        public func encode(to encoder: any Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(id, forKey: .id); try values.encode(recordedAt, forKey: .recordedAt)
            try values.encode(calories, forKey: .calories); try values.encode(nutrients, forKey: .nutrients)
        }
    }

    public struct Workout: Codable, Equatable, Sendable {
        public let id: UUID
        public let mode: WorkoutMode
        public let activity: WorkoutActivity?
        public let startedAt: Date
        public let endedAt: Date
        public let durationMinutes: Int
        public let repetitions: Int?
        public let distanceMeters: Double?
        public let calories: Int?
        public init(_ record: WorkoutRecord) {
            id = record.id; mode = record.mode; activity = record.activity
            startedAt = record.startedAt; endedAt = record.endedAt; durationMinutes = record.durationMinutes
            repetitions = record.repetitions; distanceMeters = record.distanceMeters; calories = record.calories
        }
        private enum CodingKeys: String, CodingKey {
            case id, mode, activity, startedAt, endedAt, durationMinutes, repetitions, distanceMeters, calories
        }
        public func encode(to encoder: any Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(id, forKey: .id); try values.encode(mode, forKey: .mode)
            try values.encode(activity, forKey: .activity); try values.encode(startedAt, forKey: .startedAt)
            try values.encode(endedAt, forKey: .endedAt); try values.encode(durationMinutes, forKey: .durationMinutes)
            try values.encode(repetitions, forKey: .repetitions); try values.encode(distanceMeters, forKey: .distanceMeters)
            try values.encode(calories, forKey: .calories)
        }
    }

    public struct Wellness: Codable, Equatable, Sendable {
        public let day: String
        public let sleepMinutes: Int?
        public let condition: Int?
        public init(_ entry: WellnessEntry) { day = entry.day; sleepMinutes = entry.sleepMinutes; condition = entry.condition }
        private enum CodingKeys: String, CodingKey { case day, sleepMinutes, condition }
        public func encode(to encoder: any Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(day, forKey: .day); try values.encode(sleepMinutes, forKey: .sleepMinutes)
            try values.encode(condition, forKey: .condition)
        }
    }
}

public enum HealthReportStatus: String, Codable, Sendable { case processing, completed, failed }
public enum HealthReportReaction: String, Codable, CaseIterable, Sendable { case celebrate, encourage, rest, curious }

public struct HealthReportRecommendation: Codable, Equatable, Identifiable, Sendable {
    public let title: String
    public let detail: String
    public var id: String { title }
    public init(title: String, detail: String) { self.title = title; self.detail = detail }
}

public struct HealthReportResource: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let period: HealthReportPeriod
    public let anchorDate: String
    public let timeZone: String
    public let status: HealthReportStatus
    public let createdAt: Date
    public let model: String?
    public let metrics: HealthReportMetrics
    public let evaluation: String?
    public let recommendations: [HealthReportRecommendation]
    public let failureCode: String?
    public let reaction: HealthReportReaction?

    public init(id: UUID, period: HealthReportPeriod, anchorDate: String, timeZone: String,
                status: HealthReportStatus, createdAt: Date, model: String?, metrics: HealthReportMetrics,
                evaluation: String?, recommendations: [HealthReportRecommendation], failureCode: String?,
                reaction: HealthReportReaction? = nil) {
        self.id = id; self.period = period; self.anchorDate = anchorDate; self.timeZone = timeZone
        self.status = status; self.createdAt = createdAt; self.model = model; self.metrics = metrics
        self.evaluation = evaluation; self.recommendations = recommendations; self.failureCode = failureCode
        self.reaction = reaction
    }

    public func validate() throws {
        try metrics.validate()
        guard let zone = TimeZone(identifier: timeZone),
              let expectedWindow = try? period.window(containing: anchorDate, timeZone: zone, now: createdAt),
              expectedWindow.startDate == metrics.window.startDate, expectedWindow.endDate == metrics.window.endDate,
              expectedWindow.dayCount == metrics.window.dayCount,
              metrics.window.observedThroughDate <= expectedWindow.observedThroughDate,
              timeZone == metrics.window.timeZone,
              createdAt.timeIntervalSince1970.isFinite, createdAt.timeIntervalSince1970 > 0,
              recommendations.count <= 3,
              recommendations.allSatisfy({ HealthReportDates.validText($0.title, maximum: 80) && HealthReportDates.validText($0.detail, maximum: 500) }),
              model.map({ HealthReportDates.validText($0, maximum: 160) }) ?? true,
              evaluation.map({ HealthReportDates.validText($0, maximum: 1_200) }) ?? true,
              failureCode.map({ HealthReportDates.validText($0, maximum: 80) }) ?? true else {
            throw HealthReportError.invalidResponse
        }
        if status == .completed {
            guard model != nil, evaluation != nil, failureCode == nil, recommendations.count == 3,
                  Set(recommendations.map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }).count == 3 else {
                throw HealthReportError.invalidResponse
            }
        }
    }
}

public struct HealthReportMetrics: Codable, Equatable, Sendable {
    public let window: HealthReportWindow
    public let food: Food
    public let exercise: Exercise
    public let nutrition: Nutrition
    public let calories: Calories
    public let wellness: Wellness

    public init(window: HealthReportWindow, food: Food, exercise: Exercise, nutrition: Nutrition, calories: Calories, wellness: Wellness) {
        self.window = window; self.food = food; self.exercise = exercise; self.nutrition = nutrition; self.calories = calories; self.wellness = wellness
    }

    public struct Food: Codable, Equatable, Sendable {
        public let loggedDays: Int
        public let mealCount: Int
        public init(loggedDays: Int, mealCount: Int) { self.loggedDays = loggedDays; self.mealCount = mealCount }
    }
    public struct Exercise: Codable, Equatable, Sendable {
        public let sessionCount: Int
        public let totalMinutes: Int
        public let totalRepetitions: Int?
        public let byActivity: [Activity]
        public init(sessionCount: Int, totalMinutes: Int, totalRepetitions: Int?, byActivity: [Activity]) {
            self.sessionCount = sessionCount; self.totalMinutes = totalMinutes; self.totalRepetitions = totalRepetitions; self.byActivity = byActivity
        }
        public struct Activity: Codable, Equatable, Identifiable, Sendable {
            public let activity: WorkoutActivity?
            public let sessions: Int
            public let totalMinutes: Int
            public var id: String { activity?.rawValue ?? "unspecified" }
            public init(activity: WorkoutActivity?, sessions: Int, totalMinutes: Int) {
                self.activity = activity; self.sessions = sessions; self.totalMinutes = totalMinutes
            }
        }
    }
    public struct Nutrition: Codable, Equatable, Sendable {
        public let trackedMeals: Int
        public let totalMeals: Int
        public let carbohydratesG: Double?
        public let proteinG: Double?
        public let fatG: Double?
        public let carbohydratePercent: Double?
        public let proteinPercent: Double?
        public let fatPercent: Double?
        public init(trackedMeals: Int, totalMeals: Int, carbohydratesG: Double?, proteinG: Double?, fatG: Double?,
                    carbohydratePercent: Double?, proteinPercent: Double?, fatPercent: Double?) {
            self.trackedMeals = trackedMeals; self.totalMeals = totalMeals; self.carbohydratesG = carbohydratesG
            self.proteinG = proteinG; self.fatG = fatG; self.carbohydratePercent = carbohydratePercent
            self.proteinPercent = proteinPercent; self.fatPercent = fatPercent
        }
    }
    public struct Calories: Codable, Equatable, Sendable {
        public let totalKcal: Int
        public let averagePerLoggedDay: Double?
        public let loggedDays: Int
        public init(totalKcal: Int, averagePerLoggedDay: Double?, loggedDays: Int) {
            self.totalKcal = totalKcal; self.averagePerLoggedDay = averagePerLoggedDay; self.loggedDays = loggedDays
        }
    }
    public struct Wellness: Codable, Equatable, Sendable {
        public let sleepLoggedDays: Int
        public let averageSleepMinutes: Double?
        public let conditionLoggedDays: Int
        public let averageCondition: Double?
        public init(sleepLoggedDays: Int, averageSleepMinutes: Double?, conditionLoggedDays: Int, averageCondition: Double?) {
            self.sleepLoggedDays = sleepLoggedDays; self.averageSleepMinutes = averageSleepMinutes
            self.conditionLoggedDays = conditionLoggedDays; self.averageCondition = averageCondition
        }
    }

    public func validate() throws {
        try window.validate()
        guard (0...window.elapsedDays).contains(food.loggedDays), (0...1_000).contains(food.mealCount),
              food.loggedDays <= food.mealCount, (food.loggedDays == 0) == (food.mealCount == 0),
              (0...200).contains(exercise.sessionCount), (0...288_000).contains(exercise.totalMinutes),
              exercise.totalRepetitions.map({ (0...20_000_000).contains($0) }) ?? true,
              exercise.byActivity.count <= 7, Set(exercise.byActivity.map(\.id)).count == exercise.byActivity.count,
              exercise.byActivity.allSatisfy({ (0...200).contains($0.sessions) && (0...288_000).contains($0.totalMinutes) }),
              exercise.byActivity.reduce(0, { $0 + $1.sessions }) == exercise.sessionCount,
              exercise.byActivity.reduce(0, { $0 + $1.totalMinutes }) == exercise.totalMinutes,
              (0...food.mealCount).contains(nutrition.trackedMeals), nutrition.totalMeals == food.mealCount,
              (0...5_000_000).contains(calories.totalKcal), calories.loggedDays == food.loggedDays,
              HealthReportDates.finite(calories.averagePerLoggedDay, in: 0...5_000_000),
              (0...window.elapsedDays).contains(wellness.sleepLoggedDays),
              (0...window.elapsedDays).contains(wellness.conditionLoggedDays),
              HealthReportDates.finite(wellness.averageSleepMinutes, in: 0...1_440),
              HealthReportDates.finite(wellness.averageCondition, in: 1...5),
              (wellness.sleepLoggedDays == 0) == (wellness.averageSleepMinutes == nil),
              (wellness.conditionLoggedDays == 0) == (wellness.averageCondition == nil),
              (calories.loggedDays == 0) == (calories.averagePerLoggedDay == nil) else { throw HealthReportError.invalidResponse }
        let grams = [nutrition.carbohydratesG, nutrition.proteinG, nutrition.fatG]
        let percentages = [nutrition.carbohydratePercent, nutrition.proteinPercent, nutrition.fatPercent]
        guard grams.allSatisfy({ HealthReportDates.finite($0, in: 0...2_000_000) }),
              percentages.allSatisfy({ HealthReportDates.finite($0, in: 0...100) }),
              grams.allSatisfy({ $0 == nil }) || grams.allSatisfy({ $0 != nil }),
              percentages.allSatisfy({ $0 == nil }) || percentages.allSatisfy({ $0 != nil }),
              (nutrition.trackedMeals == 0) == grams.allSatisfy({ $0 == nil }) else { throw HealthReportError.invalidResponse }
        if percentages.contains(where: { $0 != nil }) {
            guard nutrition.trackedMeals > 0,
                  abs(percentages.compactMap { $0 }.reduce(0, +) - 100) <= 0.11 else { throw HealthReportError.invalidResponse }
        }
        let energy = (nutrition.carbohydratesG ?? 0) * 4 + (nutrition.proteinG ?? 0) * 4 + (nutrition.fatG ?? 0) * 9
        if energy > 0, percentages.contains(where: { $0 == nil }) { throw HealthReportError.invalidResponse }
    }
}

public struct HealthReportResponse: Codable, Sendable {
    public let data: HealthReportResource
    public init(data: HealthReportResource) { self.data = data }
    public func validate() throws { try data.validate() }
}

public struct HealthReportListResponse: Codable, Sendable {
    public let data: [HealthReportResource]
    public let meta: Meta
    public init(data: [HealthReportResource], meta: Meta) { self.data = data; self.meta = meta }
    public func validate() throws {
        guard data.count <= 50, Set(data.map(\.id)).count == data.count,
              meta.nextCursor.map({ !$0.isEmpty && $0.count <= 512 }) ?? true else { throw HealthReportError.invalidResponse }
        try data.forEach { try $0.validate() }
    }
    public struct Meta: Codable, Sendable {
        public let nextCursor: String?
        public init(nextCursor: String?) { self.nextCursor = nextCursor }
    }
}

public enum HealthReportCoding {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var value = encoder.singleValueContainer()
            try value.encode(formatter.string(from: date))
        }
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = APIStatus(status: "", service: "", timestamp: text).date else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid ISO-8601 timestamp"))
            }
            return date
        }
        return decoder
    }
}

public enum HealthReportError: Error, LocalizedError, Equatable, Sendable {
    case invalidPeriod, invalidRecords, tooManyRecords, requestTooLarge, invalidResponse
    public var errorDescription: String? {
        switch self {
        case .invalidPeriod: String(localized: "오늘부터 지난 366일 안의 기간과 올바른 시간대를 선택해 주세요.")
        case .invalidRecords: String(localized: "기록이 서로 일치하지 않습니다. 기록을 확인해 주세요.")
        case .tooManyRecords, .requestTooLarge: String(localized: "선택한 기간의 기록이 너무 많습니다. 더 짧은 기간을 선택해 주세요.")
        case .invalidResponse: String(localized: "리포트 응답을 읽지 못했습니다. 다시 시도해 주세요.")
        }
    }
}

private enum HealthReportDates {
    // Date-only arithmetic uses UTC so daylight-saving transitions cannot move a report boundary.
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }
    static func parseDay(_ day: String) -> Date? {
        guard UsagiState.isValidDay(day) else { return nil }
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
    static func isSupported(_ zone: TimeZone) -> Bool {
        zone.identifier == "GMT" || zone.identifier == "UTC" || TimeZone.knownTimeZoneIdentifiers.contains(zone.identifier)
    }
    static func validText(_ text: String, maximum: Int) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.count <= maximum
            && !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) && $0 != "\n" && $0 != "\t" })
    }
    static func finite(_ value: Double?, in range: ClosedRange<Double>) -> Bool {
        value.map { $0.isFinite && range.contains($0) } ?? true
    }
}
