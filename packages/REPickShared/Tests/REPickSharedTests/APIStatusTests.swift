import Foundation
import Testing
@testable import REPickShared

@Test
func statusDecodesBackendTimestampWithFractionalSeconds() throws {
    let data = Data(#"{"status":"ok","service":"RE:PICK","timestamp":"2026-10-24T01:02:03.456Z"}"#.utf8)
    let status = try JSONDecoder().decode(APIStatus.self, from: data)
    #expect(status.status == "ok")
    #expect(status.service == "RE:PICK")
    let date = try #require(status.date)
    #expect(abs(date.timeIntervalSince1970 - 1_792_803_723.456) < 0.001)
}

@Test(arguments: ["2026-10-24T01:02:03Z", "2026-10-24T01:02:03+00:00"])
func statusAcceptsWholeSecondTimestamps(timestamp: String) {
    let status = APIStatus(status: "ok", service: "RE:PICK", timestamp: timestamp)
    #expect(status.date?.timeIntervalSince1970 == 1_792_803_723)
}

@Test(arguments: ["not a date", "2026-10-24T01:02:03", "2026-10-24", "2026-13-24T01:02:03Z", "2026-02-30T01:02:03Z", "2026-10-24T24:02:03Z"])
func statusRejectsInvalidOrUnzonedTimestamps(timestamp: String) {
    #expect(APIStatus(status: "ok", service: "RE:PICK", timestamp: timestamp).date == nil)
}
