import Foundation
import Testing
@testable import REPickShared

private let testDay = Date(timeIntervalSince1970: 1_767_225_600)

private var utcCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar
}

private func configuredState(goal: Int = 6_000) throws -> UsagiState {
    var state = UsagiState(now: testDay, calendar: utcCalendar)
    try state.setProfile(heightCM: 170, weightKG: 70, targetWeightKG: 65, goalSteps: goal)
    return state
}

private func snapshot(_ state: UsagiState) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(state)
}

@Test(arguments: [2_000, 3_000, 4_000, 5_000, 6_000, 7_000, 8_000, 9_000, 10_000])
func eachHigherGoalIncreasesRewardWhileDrawsFollowTheirTier(goal: Int) throws {
    let state = try configuredState(goal: goal)
    #expect(state.daily.goalReward == goal / 1_000 * 50)
    #expect(state.daily.maximumDraws == goal / 2_000)
    if goal > 2_000 {
        let lower = try configuredState(goal: goal - 1_000)
        #expect(state.daily.goalReward > lower.daily.goalReward)
    }
}

@Test func rewardsRequireCompletionAndCannotBeClaimedTwice() throws {
    var state = try configuredState()
    #expect(throws: DomainError.self) { try state.claimReward() }
    #expect(state.points == 0)
    try state.recordSteps(6_000)
    try state.claimReward()
    #expect(state.points == 300)
    #expect(state.daily.rewardClaimed)
    let before = try snapshot(state)
    #expect(throws: DomainError.self) { try state.claimReward() }
    #expect(try snapshot(state) == before)
    try state.recordSteps(6_500)
    try state.recordSteps(6_000)
    #expect(state.daily.steps == 6_500)
}

@Test func scheduledGoalStartsOnNextDayAndRolloverPreservesWallet() throws {
    var state = try configuredState()
    try state.recordSteps(6_000)
    try state.claimReward()
    try state.addWater(250)
    try state.addMeal(name: "떡볶이", calories: 550, source: .manual, now: testDay)
    try state.setNextGoal(10_000)
    #expect(state.daily.goalSteps == 6_000)
    #expect(state.nextGoalSteps == 10_000)
    state.rollover(now: testDay.addingTimeInterval(60), calendar: utcCalendar)
    #expect(state.daily.rewardClaimed)
    state.rollover(now: testDay.addingTimeInterval(86_400), calendar: utcCalendar)
    #expect(state.daily.goalSteps == 10_000)
    #expect(state.nextGoalSteps == nil)
    #expect(state.daily.steps == 0)
    #expect(state.daily.draws == 0)
    #expect(state.daily.waterML == 0)
    #expect(state.daily.meals.isEmpty)
    #expect(!state.daily.rewardClaimed)
    #expect(state.points == 300)
    #expect(state.totalFoodCalories == 550)
    #expect(state.profile?.weightKG == 70)
    let tomorrow = state.daily.day
    state.rollover(now: testDay, calendar: utcCalendar)
    #expect(state.daily.day == tomorrow)
}

@Test func profileEditsScheduleGoalWithoutResettingReward() throws {
    var state = try configuredState()
    try state.recordSteps(6_000)
    try state.claimReward()
    try state.setProfile(heightCM: 175, weightKG: 72, targetWeightKG: 68, goalSteps: 10_000)
    #expect(state.daily.goalSteps == 6_000)
    #expect(state.nextGoalSteps == 10_000)
    #expect(state.daily.rewardClaimed)
    #expect(state.points == 300)
}

@Test func drawsRespectBudgetLimitAndDuplicateRefund() throws {
    var state = try configuredState(goal: 10_000)
    #expect(throws: DomainError.self) { try state.drawOutfit(randomIndex: 0) }
    try state.recordSteps(10_000)
    #expect(throws: DomainError.self) { try state.drawOutfit(randomIndex: 0) }
    try state.claimReward()
    let first = try state.drawOutfit(randomIndex: 0)
    #expect(first == .student)
    #expect(state.points == 400)
    #expect(state.daily.draws == 1)
    #expect(try state.drawOutfit(randomIndex: 0) == .student)
    #expect(state.points == 350)
    #expect(state.ownedOutfits.filter { $0 == .student }.count == 1)
    for _ in 0..<3 { _ = try state.drawOutfit(randomIndex: 0) }
    #expect(state.daily.draws == 5)
    #expect(state.points == 200)
    let before = try snapshot(state)
    #expect(throws: DomainError.self) { try state.drawOutfit(randomIndex: 0) }
    #expect(try snapshot(state) == before)
}

@Test func invalidDrawDoesNotChargeWallet() throws {
    var state = try configuredState(goal: 10_000)
    try state.recordSteps(10_000)
    try state.claimReward()
    let before = try snapshot(state)
    #expect(throws: DomainError.self) { try state.drawOutfit(randomIndex: -1) }
    #expect(throws: DomainError.self) { try state.drawOutfit(randomIndex: 3) }
    #expect(try snapshot(state) == before)
}

@Test func directPurchaseAndEquipRequireOwnership() throws {
    var state = try configuredState(goal: 10_000)
    #expect(throws: DomainError.self) { try state.equip(.office) }
    #expect(throws: DomainError.self) { try state.buyOutfit(.office) }
    try state.recordSteps(10_000)
    try state.claimReward()
    try state.buyOutfit(.office)
    #expect(state.points == 0)
    #expect(state.ownedOutfits.contains(.office))
    try state.equip(.office)
    #expect(state.equippedOutfit == .office)
    let before = try snapshot(state)
    #expect(throws: DomainError.self) { try state.buyOutfit(.office) }
    #expect(try snapshot(state) == before)
}

@Test func invalidInputsLeaveStateUnchanged() throws {
    var state = try configuredState()
    let before = try snapshot(state)
    #expect(throws: DomainError.self) {
        try state.setProfile(heightCM: 0, weightKG: 70, targetWeightKG: 65, goalSteps: 6_000)
    }
    #expect(throws: DomainError.self) {
        try state.setProfile(heightCM: 170, weightKG: .nan, targetWeightKG: 65, goalSteps: 6_000)
    }
    #expect(throws: DomainError.self) {
        try state.setProfile(heightCM: 170, weightKG: 70, targetWeightKG: .infinity, goalSteps: 6_000)
    }
    #expect(throws: DomainError.self) { try state.setNextGoal(1_000) }
    #expect(throws: DomainError.self) { try state.setNextGoal(2_500) }
    #expect(throws: DomainError.self) { try state.setNextGoal(11_000) }
    #expect(throws: DomainError.self) { try state.recordSteps(-1) }
    #expect(throws: DomainError.self) { try state.addWater(-250) }
    #expect(throws: DomainError.self) {
        try state.addMeal(name: "   ", calories: 500, source: .manual, now: testDay)
    }
    #expect(throws: DomainError.self) {
        try state.addMeal(name: "Rice", calories: -1, source: .manual, now: testDay)
    }
    #expect(try snapshot(state) == before)
}

@Test func avatarRespondsToFoodWithoutChangingMeasuredBMI() throws {
    var state = try configuredState()
    let bmi = try #require(state.profile?.bmi)
    let scale = state.bodyScale
    let targetScale = state.targetBodyScale
    try state.addMeal(name: "떡볶이", calories: 550, source: .onDeviceAI, now: testDay)
    #expect(state.bodyScale > scale)
    #expect(state.targetBodyScale == targetScale)
    #expect(state.profile?.bmi == bmi)
    #expect(state.totalFoodCalories == 550)
    #expect(state.daily.meals.first?.source == .onDeviceAI)
    #expect(abs(bmi - (70 / (1.7 * 1.7))) < 0.000_001)
}

@Test func localSaveRoundTripsAndStartsFreshOnlyWhenMissing() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("state.json")
    let store = LocalSaveStore(fileURL: file)
    let fresh = try await store.load(now: testDay, calendar: utcCalendar)
    #expect(fresh.profile == nil)
    var state = try configuredState()
    try state.addWater(250)
    try state.addMeal(name: "Lunch", calories: 600, source: .manual, now: testDay)
    try await store.save(state)
    let reloaded = try await store.load(now: testDay, calendar: utcCalendar)
    #expect(try snapshot(reloaded) == snapshot(state))
}

@Test func malformedSaveIsPreservedAndDoesNotBecomeFreshState() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("state.json")
    let malformed = Data("{broken save".utf8)
    try malformed.write(to: file)
    let store = LocalSaveStore(fileURL: file)
    await #expect(throws: (any Error).self) { try await store.load(now: testDay, calendar: utcCalendar) }
    #expect(try Data(contentsOf: file) == malformed)
}

@Test(arguments: ["negativePoints", "futureVersion", "unownedEquipment", "duplicateOwnership", "invalidClaim", "invalidDay"])
func invalidDecodedSaveIsRejectedWithoutOverwrite(corruption: String) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("state.json")
    var json = try #require(JSONSerialization.jsonObject(with: snapshot(configuredState())) as? [String: Any])
    switch corruption {
    case "negativePoints": json["points"] = -1
    case "futureVersion": json["schemaVersion"] = 99
    case "unownedEquipment": json["equippedOutfit"] = "office"
    case "duplicateOwnership": json["ownedOutfits"] = ["basic", "basic"]
    default:
        var daily = try #require(json["daily"] as? [String: Any])
        if corruption == "invalidDay" {
            daily["day"] = "2026-02-31"
        } else {
            daily["rewardClaimed"] = true
        }
        json["daily"] = daily
    }
    let corrupted = try JSONSerialization.data(withJSONObject: json, options: .sortedKeys)
    try corrupted.write(to: file)
    let store = LocalSaveStore(fileURL: file)
    await #expect(throws: (any Error).self) { try await store.load(now: testDay, calendar: utcCalendar) }
    #expect(try Data(contentsOf: file) == corrupted)
}
