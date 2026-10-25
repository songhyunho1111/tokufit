import Foundation
import REPickShared

@main
enum GrowthFixture {
    static func main() throws {
        let mode = CommandLine.arguments.dropFirst().first ?? "milestone"
        let output = CommandLine.arguments.dropFirst(2).first ?? "/tmp/repick-growth-fixture.json"
        guard ["milestone", "earned", "missed"].contains(mode) else { fatalError("Unknown fixture mode") }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -9, to: today)!
        var state = UsagiState(now: start, calendar: calendar)
        try state.setProfile(heightCM: 170, weightKG: 70, targetWeightKG: 67, goalSteps: 6_000)
        try state.setPreferences(CompanionPreferences(name: "우사기", goalTitle: "매일 30분 걷기"))
        for offset in -9...(mode == "missed" ? -2 : -1) {
            let day = calendar.date(byAdding: .day, value: offset, to: today)!
            try state.checkIn(now: day, calendar: calendar)
        }
        state.rollover(now: now, calendar: calendar)
        try state.addMeal(name: "검증용 아침", calories: 500, source: .manual, now: now)
        try state.addMeal(name: "검증용 점심", calories: 740, source: .manual, now: now)
        try state.recordWellness(day: state.daily.day, sleepMinutes: 400, condition: 4, now: now, calendar: calendar)
        let session = try state.startWorkout(mode: .indoor, now: now.addingTimeInterval(-1_800), activity: .strength)
        try state.finishWorkout(durationMinutes: 30, now: now, sessionID: session.id, calendar: calendar)
        try state.recordSteps(6_000)
        if mode == "earned" { try state.checkIn(now: now, calendar: calendar) }
        try state.validate()
        precondition(state.freeDraws == (mode == "earned" ? 1 : 0))
        precondition(state.attendanceNeedsAttention == (mode == "missed"))
        precondition(state.totalExerciseCalories == 70 && state.totalStrengthMinutes == 30)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(state).write(to: URL(fileURLWithPath: output), options: .atomic)
        print("Validated synthetic \(mode) fixture: streak \(state.attendanceStreak), free draws \(state.freeDraws), no owner data.")
    }
}
