import Foundation
import Testing
@testable import REPickShared

@Test func legacyProfileWithoutGenderDecodesUnchanged() throws {
    let data = Data(#"{"heightCM":170,"weightKG":70,"targetWeightKG":65}"#.utf8)
    let profile = try JSONDecoder().decode(UserProfile.self, from: data)
    #expect(profile.gender == nil)
    #expect(profile.heightCM == 170)
    #expect(profile.weightKG == 70)
    #expect(profile.targetWeightKG == 65)
    #expect(profile.bmi == 70 / pow(1.70, 2))
}

@Test func legacySaveWithoutGenderKeepsProgressAndOwnership() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appending(path: "legacy.json")
    let data = Data(#"{"schemaVersion":1,"profile":{"heightCM":170,"weightKG":70,"targetWeightKG":65},"daily":{"day":"2026-10-24","goalSteps":6000,"steps":6500,"rewardClaimed":true,"draws":1,"waterML":250,"meals":[]},"points":200,"ownedOutfits":["basic","student"],"equippedOutfit":"student","totalFoodCalories":0}"#.utf8)
    try data.write(to: file, options: .atomic)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    let now = try #require(ISO8601DateFormatter().date(from: "2026-10-24T12:00:00Z"))
    let store = LocalSaveStore(fileURL: file)
    let state = try await store.load(now: now, calendar: calendar)
    #expect(state.profile?.gender == nil)
    #expect(state.profile?.weightKG == 70)
    #expect(state.points == 200)
    #expect(state.daily.steps == 6_500)
    #expect(state.daily.rewardClaimed)
    #expect(state.daily.draws == 1)
    #expect(state.daily.waterML == 250)
    #expect(state.equippedOutfit == .student)
    #expect(state.ownedOutfits == [.basic, .student])
    try await store.save(state)
    #expect(try await store.load(now: now, calendar: calendar) == state)
}

@Test(arguments: ProfileGender.allCases)
func genderSelectionRoundTripsWithoutChangingBodyCalculation(gender: ProfileGender) throws {
    var state = UsagiState()
    try state.setProfile(heightCM: 170, weightKG: 70, targetWeightKG: 65, goalSteps: 6_000, gender: gender)
    let data = try JSONEncoder().encode(state)
    let restored = try JSONDecoder().decode(UsagiState.self, from: data)
    try restored.validate()
    #expect(restored == state)
    #expect(restored.profile?.gender == gender)
    #expect(restored.schemaVersion == 1)
    let ungendered = try UserProfile(heightCM: 170, weightKG: 70, targetWeightKG: 65)
    #expect(restored.profile?.bmi == ungendered.bmi)
    #expect(restored.profile?.targetBMI == ungendered.targetBMI)
}

@Test func legacyProfileEditsPreserveGenderAndExplicitSelectionCanChangeIt() throws {
    var state = UsagiState()
    try state.setProfile(heightCM: 170, weightKG: 70, targetWeightKG: 65, goalSteps: 6_000, gender: .female)
    try state.setProfile(heightCM: 171, weightKG: 69, targetWeightKG: 64, goalSteps: 7_000)
    #expect(state.profile?.gender == .female)
    #expect(state.profile?.heightCM == 171)
    #expect(state.nextGoalSteps == 7_000)
    try state.setProfile(heightCM: 171, weightKG: 69, targetWeightKG: 64, goalSteps: 6_000, gender: .notSpecified)
    #expect(state.profile?.gender == .notSpecified)
    let before = state
    #expect(throws: DomainError.self) {
        try state.setProfile(heightCM: 0, weightKG: 69, targetWeightKG: 64, goalSteps: 6_000, gender: .male)
    }
    #expect(state == before)
}

@Test func unknownGenderValueIsRejected() {
    let data = Data(#"{"heightCM":170,"weightKG":70,"targetWeightKG":65,"gender":"unknown"}"#.utf8)
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(UserProfile.self, from: data) }
}
