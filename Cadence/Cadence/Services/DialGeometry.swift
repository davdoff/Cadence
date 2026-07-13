import Foundation
import CoreGraphics

/// Pure angle↔time math for `ClockTimePicker`'s two-lap 24-hour dial.
/// Kept out of the View (CLAUDE.md: decision logic stays in services) so it
/// can be unit-tested and hand-ported later.
///
/// The dial covers 24 h in **two full revolutions** of a 12-hour face:
/// 720° of accumulated rotation for 1440 minutes, so **1° = 2 minutes** and a
/// 15-minute detent is 7.5°. Lap 0 (0°–360°) is AM, lap 1 (360°–720°) is PM.
enum DialGeometry {
    /// Accumulated rotation spanning the whole day (2 × 360°).
    static let totalDegrees = 720.0
    /// Detent size while dragging, in minutes.
    static let snapStep = 15
    /// Last dial-selectable minute of the day (23:45). Snapping 23:53+ would
    /// round to 1440 = next-day midnight, which `bySettingHour` can't express.
    static let maxSnappedMinutes = 1425

    // MARK: - Angle ↔ time

    static func totalAngle(fromMinutes minutes: Int) -> Double {
        Double(minutes) * 0.5
    }

    static func minutes(fromTotalAngle angle: Double) -> Int {
        Int((angle * 2).rounded())
    }

    /// Where a hand points on the 12-hour face, in degrees clockwise from
    /// 12 o'clock, in [0, 360). AM and PM times share a face angle — that
    /// ambiguity is why the picker shows an explicit AM/PM control.
    static func faceAngle(forMinutes minutes: Int) -> Double {
        let a = totalAngle(fromMinutes: minutes).truncatingRemainder(dividingBy: 360)
        return a < 0 ? a + 360 : a
    }

    /// Nearest 15-minute detent, clamped to the dial's selectable range.
    static func snapped(_ minutes: Int) -> Int {
        let s = Int((Double(minutes) / Double(snapStep)).rounded()) * snapStep
        return min(max(s, 0), maxSnappedMinutes)
    }

    // MARK: - Drag support

    /// Unwraps the atan2 seam at 12 o'clock: keeps a frame-to-frame finger
    /// delta in (-180°, 180°] so a drag crossing the top of the dial doesn't
    /// register as a ~360° jump (which would teleport the time by 12 h).
    static func unwrappedDelta(from previous: Double, to current: Double) -> Double {
        var d = current - previous
        if d > 180 { d -= 360 } else if d < -180 { d += 360 }
        return d
    }

    /// Finger angle in degrees clockwise from 12 o'clock, in [0, 360).
    /// Screen coordinates are y-down, so "up" is `-dy`.
    static func fingerAngle(of point: CGPoint, around center: CGPoint) -> Double {
        let radians = atan2(point.x - center.x, -(point.y - center.y))
        let degrees = radians * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }

    /// Shortest angular distance between two face angles, in [0, 180].
    /// Used to grab whichever hand is nearer to the touch.
    static func faceDistance(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return d > 180 ? 360 - d : d
    }
}
