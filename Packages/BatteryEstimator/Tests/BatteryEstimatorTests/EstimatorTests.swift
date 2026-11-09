import Testing
import Foundation
@testable import BatteryEstimator

// Swift Testing form of the brief's XCTest suite (XCTest is not shipped with the Command Line
// Tools). Same names, values and expectations.
struct EstimatorTests {
    private func s(_ t: TimeInterval, _ l: Int, _ c: Bool = false) -> BatterySample { BatterySample(t: t, l: l, c: c) }

    @Test func testPhaseCutsOnChargingChange() {
        let p = Estimator.phase(of: [s(0, 50, true), s(600, 52, true), s(1200, 51), s(1800, 50)])
        #expect(p == [s(1200, 51), s(1800, 50)])
    }
    @Test func testPhaseCutsOnRiseOfThreeWhileDischarging() {
        let p = Estimator.phase(of: [s(0, 60), s(600, 59), s(1200, 62), s(1800, 61)])
        #expect(p == [s(1200, 62), s(1800, 61)])
    }
    @Test func testSmallRiseIsToleratedWhileDischarging() {
        let p = Estimator.phase(of: [s(0, 60), s(600, 59), s(1200, 61), s(1800, 58)])
        #expect(p.count == 4)
    }
    @Test func testPhaseCutsOnDropWhileCharging() {
        let p = Estimator.phase(of: [s(0, 40, true), s(600, 45, true), s(1200, 44, true), s(1800, 46, true)])
        #expect(p == [s(1200, 44, true), s(1800, 46, true)])
    }
    @Test func testPhaseCutsOnBackwardTime() {
        let p = Estimator.phase(of: [s(5000, 60), s(4000, 59), s(4600, 58)])
        #expect(p == [s(4000, 59), s(4600, 58)])
    }
    @Test func testGapDoesNotCutWhenTrendHolds() {
        let p = Estimator.phase(of: [s(0, 98), s(8 * 3600, 98), s(16 * 3600, 97)])   // 8 saat uyku
        #expect(p.count == 3)
    }
    @Test func testInsufficientDataGivesNone() {
        #expect(Estimator.estimate(DeviceHistory(samples: [s(0, 80)])) == .none)
        #expect(Estimator.estimate(DeviceHistory(samples: [s(0, 80), s(300, 78)])) == .none)   // 5 dk < 10 dk
        #expect(Estimator.estimate(DeviceHistory(samples: [s(0, 80), s(1200, 79)])) == .none)  // 1 puan < 2
    }
    @Test func testDischargeEstimate() {
        // 10 puan / 1 saat, şu an 50 → 5 saat
        let e = Estimator.estimate(DeviceHistory(samples: [s(0, 60), s(1800, 55), s(3600, 50)]))
        #expect(e == .timeToEmpty(5 * 3600))
    }
    @Test func testChargeEstimate() {
        // 20 puan / 1 saat, şu an 60 → 40 puan = 2 saat
        let e = Estimator.estimate(DeviceHistory(samples: [s(0, 40, true), s(3600, 60, true)]))
        #expect(e == .timeToFull(2 * 3600))
    }
    @Test func testEstimateUsesOnlyNewestPhase() {
        let e = Estimator.estimate(DeviceHistory(samples: [s(0, 90), s(3600, 80), s(7200, 80, true), s(10800, 85, true)]))
        #expect(e == .timeToFull(3 * 3600))
    }
    @Test func testAbsurdlyLongEstimateGivesNone() {
        // 2 puan / 7 gün, şu an 98 → 343 gün > 30 gün
        let e = Estimator.estimate(DeviceHistory(samples: [s(0, 100), s(7 * 86400, 98)]))
        #expect(e == .none)
    }
    @Test func testZeroOrFullGivesNone() {
        #expect(Estimator.estimate(DeviceHistory(samples: [s(0, 5), s(3600, 0)])) == .none)
        #expect(Estimator.estimate(DeviceHistory(samples: [s(0, 90, true), s(3600, 100, true)])) == .none)
    }
}
