import Foundation
import REPickShared

@main
struct WorkoutCompletionCheck {
    static func main() throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            checks += 1
        }
        func input(minutes: String = "20", repetitions: String = "", distance: String = "", calories: String = "",
                   locale: Locale = Locale(identifier: "ko_KR")) throws -> WorkoutCompletionInput {
            try WorkoutCompletionInput(minutes: minutes, repetitions: repetitions, distanceKM: distance,
                                       calories: calories, locale: locale)
        }
        func rejects(minutes: String = "20", repetitions: String = "", distance: String = "", calories: String = "") -> Bool {
            do {
                _ = try input(minutes: minutes, repetitions: repetitions, distance: distance, calories: calories)
                return false
            } catch { return true }
        }

        let blank = try input()
        check(blank.minutes == 20, "Duration must retain actual user input")
        check(blank.repetitions == nil && blank.distanceMeters == nil && blank.calories == nil,
              "Blank optional fields must remain unknown; nil calories enables the shared estimate")
        let zeros = try input(repetitions: "0", distance: "0", calories: "0")
        check(zeros.repetitions == 0 && zeros.distanceMeters == 0 && zeros.calories == 0,
              "An explicit zero is a manual value, never replaced with an estimate")
        let whitespace = try input(minutes: " 20\n", repetitions: " 30 ", distance: " 1.25 ", calories: " 150 ")
        check(whitespace.minutes == 20 && whitespace.repetitions == 30 && whitespace.distanceMeters == 1_250
              && whitespace.calories == 150, "Whitespace and distance conversion")
        let decimalComma = try input(distance: "1,25", locale: Locale(identifier: "de_DE"))
        check(decimalComma.distanceMeters == 1_250, "Locale decimal separators remain accepted")
        let boundaries = try input(minutes: "1440", repetitions: "100000", distance: "200", calories: "10000")
        check(boundaries.minutes == 1_440 && boundaries.repetitions == 100_000
              && boundaries.distanceMeters == 200_000 && boundaries.calories == 10_000, "Upper input bounds")
        for value in ["", "0", "-1", "1441", "1.5", "NaN", "99999999999999999999999999"] {
            check(rejects(minutes: value), "Invalid duration: \(value)")
        }
        for value in ["-1", "100001", "1.5"] { check(rejects(repetitions: value), "Invalid repetitions") }
        for value in ["-1", "200.01", "nan", "inf"] { check(rejects(distance: value), "Invalid distance") }
        for value in ["-1", "10001", "1.5", "inf"] { check(rejects(calories: value), "Invalid calories") }

        func estimate(_ minutes: String, _ activity: WorkoutActivity? = .walking, _ weight: Double? = 60) -> Int? {
            WorkoutCompletionInput.estimateCalories(minutes: minutes, activity: activity, weightKG: weight)
        }
        check(estimate("20") == ExerciseEnergy.estimateCalories(activity: .walking, minutes: 20, weightKG: 60),
              "The form uses the shared estimator, not its own formula")
        check(estimate(" 20\n") == estimate("20"), "Estimate accepts the same whitespace as duration parsing")
        guard let shorter = estimate("20"), let longer = estimate("40") else {
            preconditionFailure("Known activity and valid duration must produce an estimate")
        }
        check(longer > shorter, "Changing actual duration updates the estimate")
        check(estimate("20", .strength) == 40, "Changing activity updates the estimate")
        check(estimate("20", .other) == nil && estimate("20", nil) == nil, "Other and legacy unknown remain unknown")
        check(estimate("20", .walking, nil) == nil, "Missing weight cannot fabricate an estimate")
        for value in ["", "0", "-1", "1441", "1.5", "bad"] {
            check(estimate(value) == nil, "Invalid duration has no estimate: \(value)")
        }
        check(estimate("1440", .running, 350) == nil, "Out-of-range energy is unavailable, never silently capped")
        check(estimate("20", .walking, .nan) == nil, "Nonfinite weight cannot produce a value")
        print("Workout completion: \(checks) checks passed; parsing, manual values, reactive estimate inputs and unknowns.")
    }
}
