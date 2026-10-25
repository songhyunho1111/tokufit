import Foundation
import Testing
@testable import REPickShared

@Test(arguments: ["preferences", "ownedItems", "equippedItems", "workouts"])
func explicitNullDoesNotEraseNewStateFields(key: String) throws {
    var state = UsagiState()
    try state.setProfile(heightCM: 170, weightKG: 70, targetWeightKG: 65, goalSteps: 6_000)
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
    json[key] = NSNull()
    let data = try JSONSerialization.data(withJSONObject: json)
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(UsagiState.self, from: data) }
}

@Test func decodedWardrobeRejectsUnownedAndDuplicateSlots() throws {
    var state = UsagiState()
    try state.setProfile(heightCM: 170, weightKG: 70, targetWeightKG: 65, goalSteps: 6_000)
    let encoded = try JSONEncoder().encode(state)
    var json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    json["equippedItems"] = ["shorts"]
    var bad = try JSONDecoder().decode(UsagiState.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(throws: DomainError.self) { try bad.validate() }
    json["ownedItems"] = ["shorts", "skirt"]
    json["equippedItems"] = ["shorts", "skirt"]
    bad = try JSONDecoder().decode(UsagiState.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(throws: DomainError.self) { try bad.validate() }
}
