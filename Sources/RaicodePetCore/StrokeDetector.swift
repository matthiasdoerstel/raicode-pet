import Foundation

/// Recognises petting: the pointer stroked back and forth over the pet a few times.
/// Feed it the pointer's x position while it's over the pet; it says when that adds up to a pet.
public struct StrokeDetector: Sendable {
    /// How far one stroke must travel before turning back counts.
    public var minTravel: Double = 12
    /// Direction changes needed, within `window`, for a pet.
    public var requiredReversals = 4
    public var window: TimeInterval = 2
    /// No new pet this soon after the last one.
    public var cooldown: TimeInterval = 3
    /// A pause this long between samples starts over.
    public var maxGap: TimeInterval = 0.6

    private var start: Double?
    private var extreme: Double = 0
    private var direction: Double = 0
    private var lastSample: Date?
    private var reversals: [Date] = []
    private var cooldownUntil = Date.distantPast

    public init() {}

    /// Returns true when this sample completes a pet.
    public mutating func add(x: Double, at now: Date) -> Bool {
        if let last = lastSample, now.timeIntervalSince(last) > maxGap { reset() }
        lastSample = now

        guard let origin = start else {
            start = x
            extreme = x
            return false
        }
        if direction == 0 {
            if abs(x - origin) >= minTravel {
                direction = x > origin ? 1 : -1
                extreme = x
            }
        } else if (x - extreme) * direction > 0 {
            extreme = x  // still going the same way
        } else if (extreme - x) * direction >= minTravel {
            reversals.append(now)
            direction = -direction
            extreme = x
        }

        reversals.removeAll { now.timeIntervalSince($0) > window }
        guard reversals.count >= requiredReversals, now >= cooldownUntil else { return false }
        reversals.removeAll()
        cooldownUntil = now.addingTimeInterval(cooldown)
        return true
    }

    /// The pointer left the pet: forget the strokes so far (the cooldown stays).
    public mutating func reset() {
        start = nil
        direction = 0
        lastSample = nil
        reversals.removeAll()
    }
}
