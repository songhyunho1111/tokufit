import Foundation
import REPickShared

struct OnboardingDraft: Codable, Equatable, Sendable {
    enum Step: Int, Codable, CaseIterable, Sendable {
        case height, weight, gender, goal
    }

    var schemaVersion = 1
    var step: Step = .height
    var heightCM = 170
    var weightTenthsKG = 700
    var gender: ProfileGender?
    var goalSteps = 6_000

    var weightKG: Double { Double(weightTenthsKG) / 10 }

    func validate() throws {
        guard schemaVersion == 1,
              (80...250).contains(heightCM), (200...3_500).contains(weightTenthsKG),
              (2_000...10_000).contains(goalSteps), goalSteps.isMultiple(of: 1_000),
              step != .goal || gender != nil else { throw DraftError.invalidData }
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
