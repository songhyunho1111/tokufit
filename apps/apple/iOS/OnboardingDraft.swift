import Foundation
import REPickShared

struct OnboardingDraft: Codable, Equatable, Sendable {
    enum Step: Int, Codable, CaseIterable, Sendable {
        case character = -1
        case height = 0, weight = 1, gender = 2, goal = 3
        case name = 4

        static let allCases: [Step] = [.character, .name, .height, .weight, .gender, .goal]

        var position: Int {
            guard let index = Self.allCases.firstIndex(of: self) else {
                preconditionFailure("Every onboarding step must have a display order")
            }
            return index + 1
        }

        var next: Step? { Self.allCases.dropFirst(position).first }
        var previous: Step? { Self.allCases.prefix(position - 1).last }
    }

    private(set) var schemaVersion = 3
    var step: Step = .character
    var character: CharacterKind = .usagi
    var name = CharacterKind.usagi.name
    var heightCM = 170
    var weightTenthsKG = 700
    var gender: ProfileGender?
    var goalSteps = 6_000

    var weightKG: Double { Double(weightTenthsKG) / 10 }
    var normalizedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isValidName: Bool {
        (1...24).contains(normalizedName.count)
            && !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    init() {}

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, step, character, name, heightCM, weightTenthsKG, gender, goalSteps
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let version = try values.decode(Int.self, forKey: .schemaVersion)
        guard (1...3).contains(version) else { throw DraftError.invalidData }
        step = try values.decode(Step.self, forKey: .step)
        guard (version != 1 || step != .character), (version >= 3 || step != .name) else {
            throw DraftError.invalidData
        }
        character = version == 1 && !values.contains(.character)
            ? .usagi : try values.decode(CharacterKind.self, forKey: .character)
        name = version < 3 ? try values.decodeIfPresent(String.self, forKey: .name) ?? character.name
            : try values.decode(String.self, forKey: .name)
        heightCM = try values.decode(Int.self, forKey: .heightCM)
        weightTenthsKG = try values.decode(Int.self, forKey: .weightTenthsKG)
        gender = try values.decodeIfPresent(ProfileGender.self, forKey: .gender)
        goalSteps = try values.decode(Int.self, forKey: .goalSteps)
        try validate()
    }

    func validate() throws {
        // Preserve unfinished text while editing; later steps require a valid name.
        guard schemaVersion == 3,
              step == .character || step == .name || isValidName,
              (80...250).contains(heightCM), (200...3_500).contains(weightTenthsKG),
              (2_000...10_000).contains(goalSteps), goalSteps.isMultiple(of: 1_000),
              step != .goal || gender != nil else { throw DraftError.invalidData }
    }

    mutating func selectCharacter(_ character: CharacterKind) {
        if normalizedName == self.character.name { name = character.name }
        self.character = character
    }

    func completeProfile(in state: inout UsagiState) throws {
        guard state.profile == nil else { return }
        guard step == .goal, isValidName else { throw DraftError.invalidData }
        try validate()
        try state.setProfile(heightCM: Double(heightCM), weightKG: weightKG,
                             targetWeightKG: weightKG, goalSteps: goalSteps, gender: gender)
        var preferences = state.preferences
        preferences.character = character
        preferences.name = normalizedName
        try state.setPreferences(preferences)
    }

    enum DraftError: LocalizedError {
        case invalidData
        var errorDescription: String? {
            String(localized: "입력 중이던 정보를 읽지 못했습니다. 저장된 파일은 유지됩니다.")
        }
    }
}

actor OnboardingDraftStore {
    private let fileURL: URL

    init(fileURL: URL = OnboardingDraftStore.defaultURL) {
        self.fileURL = fileURL
    }

    static var defaultURL: URL {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-testing-reset") || arguments.contains("--ui-testing-use-store") {
            return URL.temporaryDirectory.appending(path: "repick-ui-onboarding.json")
        }
        #endif
        return URL.applicationSupportDirectory
            .appending(path: "REPick", directoryHint: .isDirectory)
            // Keep the original path so version 1 drafts resume with their saved values.
            .appending(path: "onboarding-v1.json")
    }

    func load() throws -> OnboardingDraft {
        let data: Data
        do { data = try Data(contentsOf: fileURL) }
        catch CocoaError.fileReadNoSuchFile { return OnboardingDraft() }
        let draft = try JSONDecoder().decode(OnboardingDraft.self, from: data)
        try draft.validate()
        return draft
    }

    func save(_ draft: OnboardingDraft) throws {
        try Task.checkCancellation()
        try draft.validate()
        let data = try JSONEncoder().encode(draft)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
        #else
        try data.write(to: fileURL, options: .atomic)
        #endif
    }

    #if DEBUG
    func resetForUITestIfRequested() throws {
        guard ProcessInfo.processInfo.arguments.contains("--ui-testing-reset") else { return }
        do { try FileManager.default.removeItem(at: fileURL) }
        catch CocoaError.fileNoSuchFile { return }
    }
    #endif
}
