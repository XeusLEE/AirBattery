import Foundation

/// Remaining time derived from a device's history: to empty while discharging, to full while charging.
public enum Estimate: Equatable {
    case none
    case timeToEmpty(TimeInterval)
    case timeToFull(TimeInterval)
}

/// Linear remaining-time estimator over the newest consistent phase of a `DeviceHistory`.
public enum Estimator {
    /// A phase must span at least this much time before it yields an estimate.
    public static let minimumSpan: TimeInterval = 600
    /// ...and its level must have moved by at least this many points.
    public static let minimumLevelDelta = 2
    /// While discharging, a rise of fewer than this many points between consecutive samples is tolerated.
    public static let riseTolerance = 3
    /// Projections longer than this are meaningless and reported as `.none`.
    public static let maximumEstimate: TimeInterval = 30 * 86400

    /// The newest run of samples sharing the newest sample's charging state and trend, in chronological
    /// order. Walks backwards from the newest sample and stops at the first sample that breaks the run.
    public static func phase(of samples: [BatterySample]) -> [BatterySample] {
        guard let newest = samples.last else { return [] }
        var start = samples.count - 1
        while start > 0, belongs(older: samples[start - 1], newer: samples[start], charging: newest.c) {
            start -= 1
        }
        return Array(samples[start...])
    }

    /// Whether `older` continues the phase that `newer` (its successor) belongs to.
    private static func belongs(older: BatterySample, newer: BatterySample, charging: Bool) -> Bool {
        guard older.c == charging, older.t <= newer.t else { return false }
        return charging ? newer.l >= older.l : newer.l - older.l < riseTolerance
    }

    /// Projects the newest phase's slope to empty (discharging) or full (charging). `.none` when the
    /// phase is too short in time or level, or the projection is non-positive or absurdly long.
    public static func estimate(_ history: DeviceHistory) -> Estimate {
        let ph = phase(of: history.samples)
        guard ph.count >= 2, let first = ph.first, let last = ph.last else { return .none }
        let span = last.t - first.t
        guard span >= minimumSpan else { return .none }
        let charging = last.c
        let delta = charging ? last.l - first.l : first.l - last.l
        guard delta >= minimumLevelDelta else { return .none }
        let remaining = charging ? 100 - last.l : last.l
        let seconds = Double(remaining) * span / Double(delta)
        guard seconds > 0, seconds <= maximumEstimate else { return .none }
        return charging ? .timeToFull(seconds) : .timeToEmpty(seconds)
    }
}
