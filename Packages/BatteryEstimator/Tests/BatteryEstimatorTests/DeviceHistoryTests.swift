import Testing
import Foundation
@testable import BatteryEstimator

// Swift Testing form of the brief's XCTest suite (XCTest is not shipped with the Command Line
// Tools). Same names, values and expectations; `record` results are bound to a `let` first
// because `#expect` cannot evaluate a mutating call on the captured value.
struct DeviceHistoryTests {
    @Test func testFirstSampleIsRecorded() {
        var h = DeviceHistory()
        let recorded = h.record(level: 80, charging: false, at: 1000)
        #expect(recorded)
        #expect(h.samples == [BatterySample(t: 1000, l: 80, c: false)])
    }
    @Test func testUnchangedReadingWithinHeartbeatIsDropped() {
        var h = DeviceHistory(samples: [BatterySample(t: 1000, l: 80, c: false)])
        let recorded = h.record(level: 80, charging: false, at: 1000 + 1799)
        #expect(!recorded)
        #expect(h.samples.count == 1)
    }
    @Test func testUnchangedReadingAfterHeartbeatIsRecorded() {
        var h = DeviceHistory(samples: [BatterySample(t: 1000, l: 80, c: false)])
        let recorded = h.record(level: 80, charging: false, at: 1000 + 1800)
        #expect(recorded)
        #expect(h.samples.count == 2)
    }
    @Test func testLevelChangeIsRecorded() {
        var h = DeviceHistory(samples: [BatterySample(t: 1000, l: 80, c: false)])
        let recorded = h.record(level: 79, charging: false, at: 1060)
        #expect(recorded)
    }
    @Test func testChargingChangeIsRecorded() {
        var h = DeviceHistory(samples: [BatterySample(t: 1000, l: 80, c: false)])
        let recorded = h.record(level: 80, charging: true, at: 1060)
        #expect(recorded)
    }
    @Test func testIgnoresOutlierJump() {
        var h = DeviceHistory(samples: [BatterySample(t: 1000, l: 100, c: false)])
        let outlier = h.record(level: 3, charging: false, at: 1060)      // 97 puan, 1 dk: aykırı
        #expect(!outlier)
        let later = h.record(level: 3, charging: false, at: 1000 + 600)  // 10 dk sonra kabul
        #expect(later)
    }
    @Test func testOutlierAllowedWhenChargingStateChanges() {
        var h = DeviceHistory(samples: [BatterySample(t: 1000, l: 100, c: true)])
        let recorded = h.record(level: 3, charging: false, at: 1060)
        #expect(recorded)
    }
    @Test func testPrunesOlderThanRetention() {
        var h = DeviceHistory(samples: [BatterySample(t: 0, l: 90, c: false)])
        h.record(level: 89, charging: false, at: 7 * 86400 + 1)
        #expect(h.samples.map { $0.l } == [89])
    }
    @Test func testCapsAtMaxSamples() {
        var h = DeviceHistory()
        for i in 0..<305 { h.record(level: 50, charging: false, at: TimeInterval(i * 1800)) }   // her 30 dk kalp atışı
        #expect(h.samples.count == 300)
        #expect(h.samples.first?.t == TimeInterval(5 * 1800))
    }
    @Test func testBackwardTimeIsStillRecorded() {
        var h = DeviceHistory(samples: [BatterySample(t: 5000, l: 80, c: false)])
        let recorded = h.record(level: 80, charging: false, at: 4000)
        #expect(recorded)
    }
}
