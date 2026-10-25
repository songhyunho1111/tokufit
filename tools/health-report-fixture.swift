import Foundation

extension Bundle { static var module: Bundle { .main } }

@main
enum HealthFixture {
    static func main() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let now = Date()
        guard let start = calendar.date(byAdding: .day, value: -4, to: calendar.startOfDay(for: now)) else { return }
        var state = UsagiState(now: start, calendar: calendar)
        try state.setProfile(heightCM: 170, weightKG: 70, targetWeightKG: 70, goalSteps: 6_000)
        try state.setPreferences(CompanionPreferences(name: "리포트 테스트"))
        let nutrients = try MealNutrients(carbohydratesG: 70, proteinG: 25, fatG: 20)
        for index in 0...4 {
            guard let day = calendar.date(byAdding: .day, value: index, to: start),
                  let breakfastTime = calendar.date(byAdding: .hour, value: 9, to: day),
                  let lunchTime = calendar.date(byAdding: .hour, value: 13, to: day),
                  let exerciseTime = calendar.date(byAdding: .hour, value: 17, to: day) else { return }
            let breakfast = min(breakfastTime, now)
            let lunch = min(lunchTime, now)
            let exerciseEnd = min(exerciseTime.addingTimeInterval(1_800), now)
            let exercise = max(day, exerciseEnd.addingTimeInterval(-1_800))
            state.rollover(now: day, calendar: calendar)
            try state.addMeal(name: "검증용 아침", calories: 600, source: .manual, now: breakfast, nutrients: index == 0 ? nil : nutrients)
            try state.addMeal(name: "검증용 점심", calories: 700, source: .manual, now: lunch, nutrients: nutrients)
            try state.recordWellness(day: UsagiState.dayKey(for: day, calendar: calendar), sleepMinutes: 450,
                                     condition: index % 2 == 0 ? 4 : 3, now: now, calendar: calendar)
            if index % 2 == 0 {
                let session = try state.startWorkout(mode: index == 2 ? .outdoor : .indoor, now: exercise)
                try state.finishWorkout(durationMinutes: 30, repetitions: index == 2 ? nil : 20,
                                        now: exerciseEnd, sessionID: session.id,
                                        activity: index == 2 ? .walking : .strength)
            }
        }
        try state.validate()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let output = CommandLine.arguments.dropFirst().first ?? "/tmp/repick-health-fixture.json"
        try encoder.encode(state).write(to: URL(fileURLWithPath: output), options: .atomic)
        print("Validated synthetic fixture: 10 meals across 5 days, 3 workouts, 5 wellness days, 9 macro entries.")
    }
}
