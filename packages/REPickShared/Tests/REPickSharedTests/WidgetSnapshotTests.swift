import Foundation
import Testing
@testable import REPickShared

@Test func widgetPayloadContainsOnlyPresentationDataAndRoundTrips() throws {
    let now = Date(timeIntervalSince1970: 1_792_800_000)
    var state = UsagiState(now: now)
    try state.setProfile(heightCM: 170, weightKG: 70, targetWeightKG: 65, goalSteps: 6_000)
    try state.recordSteps(2_500)
    try state.addWater(250)
    let payload = try WidgetPayload(snapshot: WidgetSnapshot(state: state, now: now), characterPNG: nil)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(payload)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(WidgetPayload.self, from: data)
    try decoded.validate()
    #expect(decoded.snapshot.steps == 2_500)
    #expect(decoded.snapshot.hasProfile)
    #expect(decoded.snapshot == payload.snapshot)
    let text = String(decoding: data, as: UTF8.self)
    #expect(!text.contains("heightCM"))
    #expect(!text.contains("weightKG"))
    #expect(!text.contains("gender"))
    #expect(!text.contains("meals"))
}

@Test func widgetMarksOldOrFutureStateStale() {
    let now = Date(timeIntervalSince1970: 1_792_800_000)
    let snapshot = WidgetSnapshot(state: UsagiState(now: now), now: now)
    #expect(!snapshot.isStale(at: now))
    #expect(snapshot.isStale(at: now.addingTimeInterval(901)))
    #expect(snapshot.isStale(at: now.addingTimeInterval(-301)))
    #expect(snapshot.isStale(at: now.addingTimeInterval(86_400)))
}

@Test func widgetRejectsCorruptSnapshotAndOversizedImage() throws {
    let snapshot = WidgetSnapshot(state: UsagiState())
    let encoder = JSONEncoder()
    let original = try encoder.encode(snapshot)
    var json = try #require(JSONSerialization.jsonObject(with: original) as? [String: Any])
    for (key, value) in [("version", 99), ("points", -1), ("steps", -2), ("waterML", 10_001)] {
        var changed = json
        changed[key] = value
        let bad = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONSerialization.data(withJSONObject: changed))
        #expect(throws: WidgetPayloadError.self) { try bad.validate() }
    }
    json["bodyScale"] = 10.0
    let badScale = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(throws: WidgetPayloadError.self) { try badScale.validate() }
    #expect(throws: WidgetPayloadError.self) { try WidgetPayload(snapshot: snapshot, characterPNG: Data([1, 2, 3])) }
    var oversized = Data([137, 80, 78, 71, 13, 10, 26, 10])
    oversized.append(Data(repeating: 0, count: 2_000_000))
    #expect(throws: WidgetPayloadError.self) { try WidgetPayload(snapshot: snapshot, characterPNG: oversized) }
}

@Test func legacyWidgetSnapshotDefaultsAndNewCharacterRoundTrip() throws {
    var state = UsagiState()
    try state.setProfile(heightCM: 170, weightKG: 70, targetWeightKG: 65, goalSteps: 6_000)
    var preferences = state.preferences
    preferences.character = .hachiware
    preferences.name = "하루"
    try state.setPreferences(preferences)
    try state.startWorkout(mode: .indoor)
    let encoder = JSONEncoder()
    let encoded = try encoder.encode(WidgetSnapshot(state: state))
    let restored = try JSONDecoder().decode(WidgetSnapshot.self, from: encoded)
    try restored.validate()
    #expect(restored.character == .hachiware)
    #expect(restored.name == "하루")
    #expect(restored.activeWorkoutMode == .indoor)
    var legacy = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    for key in ["name", "character", "equippedItems", "activeWorkoutMode"] { legacy.removeValue(forKey: key) }
    let old = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONSerialization.data(withJSONObject: legacy))
    try old.validate()
    #expect(old.character == .usagi)
    #expect(old.name == "우사기")
    #expect(old.equippedItems.isEmpty)
    #expect(old.activeWorkoutMode == nil)
    #expect(old.steps == state.daily.steps)
}
