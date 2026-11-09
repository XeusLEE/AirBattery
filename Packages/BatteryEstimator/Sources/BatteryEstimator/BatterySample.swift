import Foundation

/// One battery reading: time `t` (seconds since 1970), level `l` (0...100), charging flag `c`.
public struct BatterySample: Codable, Equatable {
    public let t: TimeInterval
    public let l: Int
    public let c: Bool

    public init(t: TimeInterval, l: Int, c: Bool) {
        self.t = t
        self.l = l
        self.c = c
    }
}

/// Sampled battery history of one device, deduplicated and bounded.
public struct DeviceHistory: Codable, Equatable {
    /// An unchanged reading is still stored once this much time has passed since the last sample.
    public static let heartbeatInterval: TimeInterval = 1800
    /// Samples older than this (relative to the newest recorded time) are dropped.
    public static let retention: TimeInterval = 7 * 86400
    /// Hard cap on stored samples; the oldest are dropped first.
    public static let maxSamples = 300
    /// A level jump of at least this many points...
    public static let outlierDelta = 25
    /// ...within this many seconds of the last sample is treated as a glitch and ignored.
    public static let outlierWindow: TimeInterval = 600

    public private(set) var samples: [BatterySample]

    public init(samples: [BatterySample] = []) {
        self.samples = samples
    }

    /// Stores the reading if it carries new information. Returns whether it was stored.
    @discardableResult
    public mutating func record(level: Int, charging: Bool, at time: TimeInterval) -> Bool {
        guard shouldRecord(level: level, charging: charging, at: time) else { return false }
        samples.append(BatterySample(t: time, l: level, c: charging))
        prune(now: time)
        return true
    }

    private func shouldRecord(level: Int, charging: Bool, at time: TimeInterval) -> Bool {
        guard let last = samples.last else { return true }
        if time < last.t { return true }
        if charging != last.c { return true }
        if abs(level - last.l) >= Self.outlierDelta && time - last.t < Self.outlierWindow { return false }
        if level != last.l { return true }
        if time - last.t >= Self.heartbeatInterval { return true }
        return false
    }

    private mutating func prune(now: TimeInterval) {
        samples.removeAll { $0.t < now - Self.retention }
        if samples.count > Self.maxSamples {
            samples.removeFirst(samples.count - Self.maxSamples)
        }
    }
}
