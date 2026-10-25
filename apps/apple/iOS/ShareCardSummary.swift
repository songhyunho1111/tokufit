import Foundation
import REPickShared

struct ShareCardSummary {
    let costumeName: String
    let height: String
    let weight: String
    let weightChange: String?
    let foodStatus: String
    let exerciseStatus: String
    let sleepStatus: String
    let message: String
    let date: String

    init(snapshot: UsagiState) {
        let style = snapshot.currentCostume?.name
            ?? (snapshot.equippedOutfit == .basic ? nil : snapshot.equippedOutfit.name)
        costumeName = [style, snapshot.preferences.character.name].compactMap { $0 }.joined(separator: " ")
        height = snapshot.profile.map { Self.measurement($0.heightCM, unit: "cm") } ?? "—"
        weight = snapshot.profile.map { Self.measurement($0.weightKG, unit: "kg") } ?? "—"
        weightChange = snapshot.weightChangeKG.map { ShareCardText.weightChange($0) }
        date = snapshot.daily.day.replacingOccurrences(of: "-", with: ".")

        let foodMessage: String
        if snapshot.daily.meals.isEmpty {
            foodStatus = String(localized: "기록 없음")
            foodMessage = String(localized: "먹은 음식을 기록해 줘.")
        } else {
            switch snapshot.nutritionStatus {
            case .within:
                foodStatus = String(localized: "범위 내")
                foodMessage = String(localized: "식사는 정한 범위 안이야.")
            case .below:
                foodStatus = String(localized: "범위 미만")
                foodMessage = String(localized: "기록한 식사가 정한 범위보다 적어.")
            case .above:
                foodStatus = String(localized: "범위 초과")
                foodMessage = String(localized: "기록한 식사가 정한 범위를 넘었어.")
            case .unconfigured, .unrecorded:
                foodStatus = String(localized: "기록 완료")
                foodMessage = String(localized: "오늘 식사를 \(snapshot.recordedCaloriesToday) kcal 기록했어.")
            }
        }

        let exerciseMessage: String
        if snapshot.daily.isGoalComplete {
            exerciseStatus = String(localized: "목표 달성")
            exerciseMessage = String(localized: "오늘 걸음 목표도 달성했어!")
        } else if snapshot.workoutMinutesToday > 0 {
            exerciseStatus = String(localized: "\(snapshot.workoutMinutesToday)분 기록")
            exerciseMessage = String(localized: "운동도 \(snapshot.workoutMinutesToday)분 기록했어.")
        } else {
            exerciseStatus = String(localized: "목표 전")
            exerciseMessage = String(localized: "걸음 목표까지 \(snapshot.daily.goalSteps - snapshot.daily.steps)보 남았어.")
        }

        let sleep = snapshot.wellnessHistory.first { $0.day == snapshot.daily.day }?.sleepMinutes
        let sleepMessage: String
        if let sleep {
            sleepStatus = sleep.isMultiple(of: 60)
                ? String(localized: "\(sleep / 60)시간")
                : String(localized: "\(sleep / 60)시간 \(sleep % 60)분")
            sleepMessage = String(localized: "수면은 \(sleepStatus) 기록돼 있어.")
        } else {
            sleepStatus = String(localized: "기록 없음")
            sleepMessage = String(localized: "수면 기록도 남겨 줘.")
        }
        message = [foodMessage, exerciseMessage, sleepMessage].joined(separator: "\n")
    }

    private static func measurement(_ value: Double, unit: String) -> String {
        let number = value.formatted(.number.locale(Locale(identifier: "ko_KR")).precision(.fractionLength(0...1)))
        return "\(number) \(unit)"
    }
}

enum ShareCardText {
    static func weightChange(_ value: Double?) -> String {
        guard let value else { return String(localized: "비교 기록 없음") }
        // Normalize sub-tenth changes to zero so rounding cannot produce a misleading -0.0.
        let rounded = (value * 10).rounded() / 10
        if rounded == 0 { return "0.0 kg" }
        return String(format: "%+.1f kg", locale: Locale(identifier: "en_US_POSIX"), rounded)
    }
}
