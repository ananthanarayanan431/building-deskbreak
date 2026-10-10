import Foundation

/// Compact countdown text for the menu, e.g. "42 min", "1 h 12 min", "under 1 min".
public enum DurationText {
    public static func short(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "now" }
        // Round up so the menu never claims "0 min" while a reminder is still pending.
        let totalMinutes = Int((seconds / 60).rounded(.up))
        if seconds < 60 { return "under 1 min" }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        switch (hours, minutes) {
        case (0, _): return "\(minutes) min"
        case (_, 0): return "\(hours) h"
        default: return "\(hours) h \(minutes) min"
        }
    }

    /// Converts a `Duration` (as produced by `SuspendingClock`) to seconds.
    public static func seconds(_ duration: Duration) -> TimeInterval {
        let (seconds, attoseconds) = duration.components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
