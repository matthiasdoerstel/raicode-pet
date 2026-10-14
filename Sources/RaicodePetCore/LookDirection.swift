import Foundation

/// Which of the 16 Codex look poses faces the pointer.
public enum LookDirection {
    public static let count = 16

    /// Pose index for a pointer offset from the pet (screen coordinates, y up).
    /// 0 = up / 12 o'clock, counting clockwise in 22.5° steps.
    public static func index(dx: Double, dy: Double) -> Int {
        var degrees = atan2(dx, dy) * 180 / .pi
        if degrees < 0 { degrees += 360 }
        return Int((degrees / 22.5).rounded()) % count
    }
}
