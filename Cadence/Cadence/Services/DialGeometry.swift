import Foundation
import CoreGraphics

/// Pure angle↔time math for `ClockTimePicker`'s single-revolution 12-hour dial.
/// Kept out of the View (CLAUDE.md: decision logic stays in services) so it
/// can be unit-tested and hand-ported later.
///
/// The face covers **12 h in one 360° revolution**, so `1° = 2 min` and a
/// 15-minute detent is 7.5°. A hand's angle is only its *position within a
/// half* — which half is normally an explicit AM/PM toggle carried in the
/// absolute minutes-of-day (0–1440), not a second lap of the dial. The one
/// exception is a live drag of the picker's end hand, which is allowed to
/// wind across the AM/PM seam (`continuousAngle`/`halfIndex` below).
enum DialGeometry {
    /// Minutes in one AM/PM half (one full revolution of the face).
    static let halfDayMinutes = 720
    /// Detent size while dragging, in minutes.
    static let snapStep = 15
    /// Last dial-selectable minute of the day (23:45). Snapping 23:53+ would
    /// round to 1440 = next-day midnight, which `bySettingHour` can't express.
    static let maxSnappedMinutes = 1425

    // MARK: - Half (AM/PM) helpers

    /// True once the absolute time has crossed noon into the PM half.
    static func isPM(_ minutes: Int) -> Bool { minutes >= halfDayMinutes }

    /// The absolute-minute offset of the half `minutes` sits in (0 = AM, 720 = PM).
    static func halfBase(_ minutes: Int) -> Int { isPM(minutes) ? halfDayMinutes : 0 }

    // MARK: - Angle ↔ time

    /// Where a hand points on the 12-hour face, in degrees clockwise from
    /// 12 o'clock, in [0, 360). AM and PM times share a face angle — that
    /// ambiguity is why the picker shows an explicit AM/PM control.
    static func faceAngle(forMinutes minutes: Int) -> Double {
        let a = (Double(minutes) * 0.5).truncatingRemainder(dividingBy: 360)
        return a < 0 ? a + 360 : a
    }

    /// Position within the half (minutes since the half's 12 o'clock), in
    /// [0, 720), from a face angle. The caller snaps and re-attaches the half.
    static func positionMinutes(fromFaceAngle angle: Double) -> Int {
        Int((normalizedAngle(angle) * 2).rounded()) % halfDayMinutes
    }

    /// Wraps any accumulated drag angle into a single revolution, [0, 360).
    static func normalizedAngle(_ angle: Double) -> Double {
        let a = angle.truncatingRemainder(dividingBy: 360)
        return a < 0 ? a + 360 : a
    }

    // MARK: - Crossing halves mid-drag (end hand only)

    /// Continuous angle for `minutes` that, unlike `faceAngle`, keeps a
    /// half-index baked in: values in the next half forward land past 360°,
    /// one half back land below 0°. Seeds/re-anchors a live drag so
    /// `halfIndex(fromContinuousAngle:)` stays consistent across the drag
    /// even after `minutes` has crossed into a different half.
    static func continuousAngle(forMinutes minutes: Int) -> Double {
        Double(minutes / halfDayMinutes) * 360 + faceAngle(forMinutes: minutes)
    }

    /// Snaps a *continuous* drag angle (unwrapped — may represent many hours
    /// of winding, not reduced to one revolution) straight to a 15-minute
    /// detent. Deliberately does the half and the within-half position in one
    /// rounding step: splitting them (round the within-half position, then
    /// separately decide the half from the raw angle) lets the two disagree
    /// by up to half a detent right at the 12 o'clock seam — e.g. 359.9°
    /// rounds its position up to a full half (720 min) and wraps to 0 while
    /// the raw angle still says "the half before", producing a spurious
    /// value far from where the finger actually is.
    static func snappedContinuousMinutes(fromContinuousAngle angle: Double) -> Int {
        let minutes = angle * 2
        return Int((minutes / Double(snapStep)).rounded()) * snapStep
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
