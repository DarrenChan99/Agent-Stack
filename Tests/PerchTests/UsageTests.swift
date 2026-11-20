import Foundation
import Testing
@testable import Perch

// Shape of GET /api/oauth/usage (fields per CodexBar's OAuthUsageResponse); extra keys must be ignored.
let usageFixture = #"""
{"five_hour":{"utilization":84.0,"resets_at":"2026-11-19T22:30:00.123456+00:00"},
 "seven_day":{"utilization":37.5,"resets_at":"2026-11-24T09:00:00+00:00"},
 "seven_day_opus":null,"extra_usage":{"is_enabled":false}}
"""#

@Test func usageDecode() throws {
    let u = try Usage.decode(Data(usageFixture.utf8))
    #expect(u.fiveHour?.pct == 84)
    #expect(u.weekly?.pct == 37.5)
    #expect(abs(u.fiveHour!.resetsAt!.timeIntervalSince(ISO8601DateFormatter().date(from: "2026-11-19T22:30:00+00:00")!)) < 1)
    #expect(u.weekly?.resetsAt != nil)
}

@Test func usageDecodeMissingWindow() throws {
    let u = try Usage.decode(Data(#"{"five_hour":{"utilization":10,"resets_at":null}}"#.utf8))
    #expect(u.fiveHour?.pct == 10 && u.fiveHour?.resetsAt == nil && u.weekly == nil)
}

@Test func resetText() {
    let now = Date(timeIntervalSince1970: 0)
    #expect(Meter.resetText(now.addingTimeInterval(6480), now: now) == "1h 48m")
    #expect(Meter.resetText(now.addingTimeInterval(59 * 60), now: now) == "59m")
    #expect(Meter.resetText(now.addingTimeInterval(50 * 3600), now: now) == "2d 2h")
}

@MainActor @Test func failureKeepsLastGoodUsage() throws {
    let f = UsageFetcher()
    #expect(f.displayUsage == nil)
    let u = try Usage.decode(Data(usageFixture.utf8))
    f.apply(u)
    #expect(f.displayUsage == u)
    f.apply(nil)
    #expect(f.displayUsage == u) // a 429 or timeout must not blank the bars
    f.apply(u)
    #expect(f.displayUsage == u)
}
