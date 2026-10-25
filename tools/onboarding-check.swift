import Foundation
import REPickShared

@main
struct OnboardingCheck {
    static func main() async throws {
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            checks += 1
        }
        let directory = URL.temporaryDirectory.appending(path: "repick-onboarding-check-\(UUID())", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "onboarding-v1.json")
        let disk = OnboardingDraftStore(fileURL: file)
        let fresh = try await disk.load()
        check(fresh.step == .character && fresh.schemaVersion == 3, "Fresh onboarding begins with character choice")
        check(fresh.name == fresh.character.name && fresh.isValidName, "Fresh draft starts with its character's default name")

        let order: [OnboardingDraft.Step] = [.character, .name, .height, .weight, .gender, .goal]
        check(OnboardingDraft.Step.allCases == order, "Name follows character without renumbering old saved steps")
        for (index, step) in order.enumerated() {
            check(step.position == index + 1, "Progress follows presentation order")
            check(step.previous == (index == 0 ? nil : order[index - 1]), "Previous step follows presentation order")
            check(step.next == (index == order.count - 1 ? nil : order[index + 1]), "Next step follows presentation order")
        }
        check(OnboardingDraft.Step.name.rawValue == 4, "Name uses a new persisted value")
        check(OnboardingDraft.Step.character.rawValue == -1, "Character keeps its version 2 persisted value")
        for (rawValue, step) in [OnboardingDraft.Step.height, .weight, .gender, .goal].enumerated() {
            check(step.rawValue == rawValue, "Version 1 step values remain unchanged")
        }

        func savedData(step: Int = 2, version: Int = 1, character: String? = nil, name: String? = nil,
                       height: Int = 181, gender: String? = "female") throws -> Data {
            var json: [String: Any] = [
                "schemaVersion": version, "step": step, "heightCM": height,
                "weightTenthsKG": 763, "goalSteps": 8_000
            ]
            if let character { json["character"] = character }
            if let name { json["name"] = name }
            if let gender { json["gender"] = gender }
            return try JSONSerialization.data(withJSONObject: json, options: .sortedKeys)
        }
        for version in [1, 2] {
            let steps: [OnboardingDraft.Step] = version == 1 ? [.height, .weight, .gender, .goal]
                : [.character, .height, .weight, .gender, .goal]
            let character: CharacterKind = version == 1 ? .usagi : .hachiware
            for step in steps {
                let original = try savedData(step: step.rawValue, version: version,
                                             character: version == 1 ? nil : character.rawValue)
                try original.write(to: file)
                let resumed = try await disk.load()
                check(resumed.step == step && resumed.schemaVersion == 3 && resumed.character == character,
                      "Version \(version) step \(step.rawValue) keeps its meaning and character")
                check(resumed.name == character.name, "An older draft missing a name uses its selected character's name")
                check(resumed.heightCM == 181 && resumed.weightTenthsKG == 763 && resumed.gender == .female
                      && resumed.goalSteps == 8_000, "Legacy measurements and choices remain intact")
                check(try Data(contentsOf: file) == original, "Loading a legacy draft does not rewrite its file")
                try await disk.save(resumed)
                check(try await disk.load() == resumed, "Migrated draft persists as version 3")
            }
        }
        try savedData(gender: nil).write(to: file)
        check(try await disk.load().gender == nil, "Unanswered legacy gender remains unanswered")
        try savedData(version: 2, character: "chiikawa", name: "내 친구").write(to: file)
        check(try await disk.load().name == "내 친구", "A name already stored in an older draft remains unchanged")
        var incomplete = UsagiState()
        do {
            try fresh.completeProfile(in: &incomplete)
            preconditionFailure("An unfinished draft cannot complete a profile")
        } catch { checks += 1 }
        check(incomplete.profile == nil, "Rejected completion leaves the state unchanged")
        for character in CharacterKind.allCases {
            var chosen = fresh
            chosen.selectCharacter(character)
            check(chosen.name == character.name, "Default name follows a new character selection")
            chosen.step = .goal
            chosen.gender = .notSpecified
            try await disk.save(chosen)
            let restored = try await disk.load()
            check(restored == chosen, "Selected \(character.rawValue) survives a draft round trip")
            var state = UsagiState()
            try restored.completeProfile(in: &state)
            check(state.profile != nil && state.preferences.character == character
                  && state.preferences.name == character.name, "New profile uses selected character and its default name")
            check(state.profile?.heightCM == Double(chosen.heightCM) && state.profile?.weightKG == chosen.weightKG,
                  "Character selection does not change entered measurements")
            var preferences = state.preferences
            preferences.name = "내 친구"
            try state.setPreferences(preferences)
            let existing = state
            var different = chosen
            different.selectCharacter(character == .usagi ? .chiikawa : .usagi)
            different.heightCM = 150
            try different.completeProfile(in: &state)
            check(state == existing, "Existing profile and custom name are never overwritten by a draft")
        }

        var custom = fresh
        custom.name = "  나의 친구  "
        check(custom.isValidName && custom.normalizedName == "나의 친구", "Surrounding spaces are trimmed for the profile")
        custom.selectCharacter(.hachiware)
        check(custom.name == "  나의 친구  ", "Changing character preserves a custom name as entered")
        custom.step = .goal
        custom.gender = .notSpecified
        try await disk.save(custom)
        let restoredCustom = try await disk.load()
        check(restoredCustom == custom, "Custom name and character survive a draft round trip")
        var namedState = UsagiState()
        try restoredCustom.completeProfile(in: &namedState)
        check(namedState.preferences.character == .hachiware && namedState.preferences.name == "나의 친구",
              "Completion uses the selected character and normalized custom name")

        for step in [OnboardingDraft.Step.character, .name] {
            var unfinished = fresh
            unfinished.step = step
            unfinished.name = ""
            try await disk.save(unfinished)
            check(try await disk.load() == unfinished, "An unfinished early name survives closing and reopening onboarding")
        }

        var boundary = custom
        boundary.name = String(repeating: "가", count: 24)
        check(boundary.isValidName, "Twenty-four user-perceived characters are accepted")
        for name in ["", "   ", String(repeating: "가", count: 25), "친구\n", "\t친구", "친\u{0000}구"] {
            var invalid = custom
            invalid.name = name
            check(!invalid.isValidName, "Empty, overlong and raw control-character names are invalid")
            var state = UsagiState()
            let original = state
            do {
                try invalid.completeProfile(in: &state)
                preconditionFailure("An invalid name cannot complete a profile")
            } catch { checks += 1 }
            check(state == original, "Rejected names leave profile and preferences unchanged")
            let savedBeforeFailure = try Data(contentsOf: file)
            do {
                try await disk.save(invalid)
                preconditionFailure("A final-step draft cannot persist an invalid name")
            } catch { checks += 1 }
            check(try Data(contentsOf: file) == savedBeforeFailure, "Rejected final-step name leaves the previous draft intact")
        }

        for malformed in [
            try savedData(version: 4), try savedData(step: 4), try savedData(step: -1),
            try savedData(step: 4, version: 2, character: "usagi"),
            try savedData(version: 2, character: "unknown"), try savedData(version: 2),
            try savedData(version: 3, character: "usagi"),
            try savedData(step: 5, version: 3, character: "usagi", name: "친구"),
            try savedData(height: 0), try savedData(step: 3, gender: nil)
        ] {
            try malformed.write(to: file)
            do {
                _ = try await disk.load()
                preconditionFailure("Invalid saved input must fail")
            } catch { checks += 1 }
            check(try Data(contentsOf: file) == malformed, "Rejected input remains on disk for recovery")
        }
        print("Onboarding: \(checks) checks passed; character/name choices, old-step migration, navigation, persistence, profile preservation and invalid input.")
    }
}
