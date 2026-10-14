import Foundation

/// Compact durations for the bubble and menu: "4 min", "1 h 5 min". Nothing under a minute.
public enum DurationText {
    public static func short(_ seconds: TimeInterval) -> String? {
        let minutes = Int(seconds / 60)
        guard minutes >= 1 else { return nil }
        let h = minutes / 60, m = minutes % 60
        switch (h, m) {
        case (0, _): return "\(m) min"
        case (_, 0): return "\(h) h"
        default: return "\(h) h \(m) min"
        }
    }
}

extension SessionRecord {
    /// The duration worth showing: how long it's been waiting, or how long the finished task took.
    public func elapsedText(now: Date) -> String? {
        switch state {
        case .waiting: return DurationText.short(timeInState(now: now))
        case .done: return taskDuration.flatMap(DurationText.short)
        default: return nil
        }
    }
}
