import Testing
import Foundation
@testable import BatteryEstimator

// Swift Testing form of the brief's XCTest suite (XCTest is not shipped with the Command Line
// Tools). Same names, values and expectations.
struct DurationPartsTests {
    @Test func testUnderAnHourRoundsToFiveMinutes() {
        #expect(DurationParts.from(seconds: 53 * 60) == DurationParts(days: 0, hours: 0, minutes: 55))
        #expect(DurationParts.from(seconds: 90) == DurationParts(days: 0, hours: 0, minutes: 5))      // en az 5
        #expect(DurationParts.from(seconds: 58 * 60) == DurationParts(days: 0, hours: 1, minutes: 0)) // 60 → 1 sa
    }
    @Test func testUnderADayGivesHoursAndRoundedMinutes() {
        #expect(DurationParts.from(seconds: 3 * 3600 + 12 * 60) == DurationParts(days: 0, hours: 3, minutes: 10))
        #expect(DurationParts.from(seconds: 3 * 3600 + 2 * 60) == DurationParts(days: 0, hours: 3, minutes: 0))
        #expect(DurationParts.from(seconds: 23 * 3600 + 59 * 60) == DurationParts(days: 1, hours: 0, minutes: 0))
    }
    @Test func testDayOrMoreGivesWholeDays() {
        #expect(DurationParts.from(seconds: 6.4 * 86400) == DurationParts(days: 6, hours: 0, minutes: 0))
        #expect(DurationParts.from(seconds: 86400) == DurationParts(days: 1, hours: 0, minutes: 0))
    }
}
