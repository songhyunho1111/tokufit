import Foundation
import REPickShared

@main
enum ShareCardSummaryCheck {
    static func main() throws {
        let now = Date()
        var state = UsagiState(now: now)
        try state.setProfile(heightCM: 170, weightKG: 60, targetWeightKG: 60, goalSteps: 6_000)
        var preferences = state.preferences
        preferences.calorieMinimum = 1_300
        preferences.calorieMaximum = 1_800
        try state.setPreferences(preferences)

        let empty = ShareCardSummary(snapshot: state)
        precondition(empty.height == "170 cm" && empty.weight == "60 kg")
        precondition(empty.foodStatus == "기록 없음" && empty.sleepStatus == "기록 없음")
        precondition(empty.exerciseStatus == "목표 전" && empty.message.replacingOccurrences(of: ",", with: "").contains("6000"))

        try state.addMeal(name: "Lunch", calories: 1_500, source: .manual, now: now, kind: .lunch)
        try state.recordSteps(6_000)
        try state.recordWellness(day: state.daily.day, sleepMinutes: 420, condition: 4, now: now)
        let complete = ShareCardSummary(snapshot: state)
        precondition(complete.foodStatus == "범위 내" && complete.exerciseStatus == "목표 달성")
        precondition(complete.sleepStatus == "7시간" && complete.message.contains("7시간"))

        try state.addMeal(name: "Dinner", calories: 500, source: .manual, now: now, kind: .dinner)
        try state.recordWellness(day: state.daily.day, sleepMinutes: 0, now: now)
        let updated = ShareCardSummary(snapshot: state)
        precondition(updated.foodStatus == "범위 초과" && updated.sleepStatus == "0시간")
        precondition(updated.date == state.daily.day.replacingOccurrences(of: "-", with: "."))
        precondition(ShareCardText.weightChange(-0.01) == "0.0 kg")
        print("Share card summary: missing records, actual metrics, updates and weight rounding passed.")
    }
}
