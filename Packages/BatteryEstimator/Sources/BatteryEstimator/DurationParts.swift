import Foundation

/// A duration split into display-ready `days`, `hours` and `minutes`, rounded for a "time left" label.
public struct DurationParts: Equatable {
    public let days: Int
    public let hours: Int
    public let minutes: Int

    /// Rounds `seconds` for display: under an hour to 5-minute steps (at least 5); under a day to
    /// hours plus 5-minute steps; otherwise to whole days (at least 1). A value that rounds up to a
    /// full hour or day carries over (58 min → 1 h, 23 h 59 min → 1 d).
    public static func from(seconds: TimeInterval) -> DurationParts {
        if seconds < 3600 {
            let minutes = max(5, Int((seconds / 60 / 5).rounded()) * 5)
            if minutes == 60 { return DurationParts(days: 0, hours: 1, minutes: 0) }
            return DurationParts(days: 0, hours: 0, minutes: minutes)
        }
        if seconds < 86400 {
            let totalMinutes = Int((seconds / 60 / 5).rounded()) * 5
            let hours = totalMinutes / 60
            if hours == 24 { return DurationParts(days: 1, hours: 0, minutes: 0) }
            return DurationParts(days: 0, hours: hours, minutes: totalMinutes % 60)
        }
        return DurationParts(days: max(1, Int((seconds / 86400).rounded())), hours: 0, minutes: 0)
    }
}
