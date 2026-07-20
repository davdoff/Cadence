import XCTest
@testable import Cadence

final class DialGeometryTests: XCTestCase {

    // MARK: - Face angle (12-hour single revolution, AM/PM ambiguity by design)

    func testFaceAngleSharedBetweenHalves() {
        XCTAssertEqual(DialGeometry.faceAngle(forMinutes: 540), 270)   // 9:00 AM
        XCTAssertEqual(DialGeometry.faceAngle(forMinutes: 1260), 270)  // 9:00 PM → same face
        XCTAssertEqual(DialGeometry.faceAngle(forMinutes: 720), 0)     // noon points at 12
        XCTAssertEqual(DialGeometry.faceAngle(forMinutes: 0), 0)       // midnight points at 12
        XCTAssertEqual(DialGeometry.faceAngle(forMinutes: 180), 90)    // 3:00 AM points at 3
    }

    // MARK: - AM/PM half helpers

    func testHalfHelpers() {
        XCTAssertFalse(DialGeometry.isPM(0))
        XCTAssertFalse(DialGeometry.isPM(540))
        XCTAssertTrue(DialGeometry.isPM(720))
        XCTAssertTrue(DialGeometry.isPM(1260))
        XCTAssertEqual(DialGeometry.halfBase(540), 0)     // 9:00 AM sits in the AM half
        XCTAssertEqual(DialGeometry.halfBase(1260), 720)  // 9:00 PM sits in the PM half
    }

    // MARK: - Face angle ↔ position within the half

    func testPositionMinutesRoundTripsWithinHalf() {
        for minutes in stride(from: 0, to: DialGeometry.halfDayMinutes, by: 15) {
            let angle = DialGeometry.faceAngle(forMinutes: minutes)
            XCTAssertEqual(DialGeometry.positionMinutes(fromFaceAngle: angle), minutes)
        }
    }

    func testPositionMinutesWrapsAtNoon() {
        // 360° (== 0°) is 12 o'clock, the *start* of the half, not minute 720.
        XCTAssertEqual(DialGeometry.positionMinutes(fromFaceAngle: 360), 0)
    }

    // MARK: - Angle normalization (a drag can wind past a single revolution)

    func testNormalizedAngle() {
        XCTAssertEqual(DialGeometry.normalizedAngle(-10), 350)
        XCTAssertEqual(DialGeometry.normalizedAngle(370), 10)
        XCTAssertEqual(DialGeometry.normalizedAngle(360), 0)
        XCTAssertEqual(DialGeometry.normalizedAngle(90), 90)
    }

    // MARK: - Snapping (15-min detents, clamped to the selectable day)

    func testSnappedRoundsToNearestDetent() {
        XCTAssertEqual(DialGeometry.snapped(547), 540)   // 9:07 → 9:00
        XCTAssertEqual(DialGeometry.snapped(553), 555)   // 9:13 → 9:15
        XCTAssertEqual(DialGeometry.snapped(540), 540)   // already on a detent
    }

    func testSnappedClampsToDay() {
        XCTAssertEqual(DialGeometry.snapped(-5), 0)
        // 23:59 must not round up to 1440 (= next-day midnight).
        XCTAssertEqual(DialGeometry.snapped(1439), DialGeometry.maxSnappedMinutes)
    }

    // MARK: - Seam unwrapping (crossing 12 o'clock mid-drag)

    func testUnwrappedDeltaAcrossSeam() {
        XCTAssertEqual(DialGeometry.unwrappedDelta(from: 359, to: 1), 2)     // clockwise over the top
        XCTAssertEqual(DialGeometry.unwrappedDelta(from: 1, to: 359), -2)    // counter-clockwise over the top
        XCTAssertEqual(DialGeometry.unwrappedDelta(from: 90, to: 100), 10)   // ordinary move untouched
        XCTAssertEqual(DialGeometry.unwrappedDelta(from: 100, to: 90), -10)
    }

    // MARK: - Finger angle (0° at 12 o'clock, clockwise, y-down coords)

    func testFingerAngleAtCardinalPoints() {
        let c = CGPoint(x: 100, y: 100)
        XCTAssertEqual(DialGeometry.fingerAngle(of: CGPoint(x: 100, y: 20), around: c), 0)    // top
        XCTAssertEqual(DialGeometry.fingerAngle(of: CGPoint(x: 180, y: 100), around: c), 90)  // right
        XCTAssertEqual(DialGeometry.fingerAngle(of: CGPoint(x: 100, y: 180), around: c), 180) // bottom
        XCTAssertEqual(DialGeometry.fingerAngle(of: CGPoint(x: 20, y: 100), around: c), 270)  // left
    }

    // MARK: - Nearest-hand grab

    func testFaceDistanceShortestWay() {
        XCTAssertEqual(DialGeometry.faceDistance(350, 10), 20)   // across the seam
        XCTAssertEqual(DialGeometry.faceDistance(10, 350), 20)
        XCTAssertEqual(DialGeometry.faceDistance(90, 270), 180)  // opposite hands
        XCTAssertEqual(DialGeometry.faceDistance(45, 45), 0)
    }

    // MARK: - Crossing halves mid-drag (end hand only)

    func testContinuousAngleMatchesFaceAngleWithinFirstHalf() {
        XCTAssertEqual(DialGeometry.continuousAngle(forMinutes: 0), 0)
        XCTAssertEqual(DialGeometry.continuousAngle(forMinutes: 540), 270)   // 9:00 AM
        XCTAssertEqual(DialGeometry.continuousAngle(forMinutes: 719), DialGeometry.faceAngle(forMinutes: 719))
    }

    func testContinuousAngleAddsALapPerHalf() {
        // 9:00 PM (1260 min) is one half past 9:00 AM (540 min): same face
        // angle (270°), but continuousAngle keeps them 360° apart.
        XCTAssertEqual(DialGeometry.continuousAngle(forMinutes: 1260), 630)
        XCTAssertEqual(DialGeometry.continuousAngle(forMinutes: 720), 360)   // noon = one lap exactly
    }

    func testSnappedContinuousMinutesTracksMultipleHalves() {
        XCTAssertEqual(DialGeometry.snappedContinuousMinutes(fromContinuousAngle: 90), 180)   // 3:00, well inside half 0
        XCTAssertEqual(DialGeometry.snappedContinuousMinutes(fromContinuousAngle: 360), 720)  // exactly noon
        XCTAssertEqual(DialGeometry.snappedContinuousMinutes(fromContinuousAngle: 390), 780)  // 1:00's face (30°), one half further
        XCTAssertEqual(DialGeometry.snappedContinuousMinutes(fromContinuousAngle: -15), -30)  // wound back before start
    }

    func testSnappedContinuousMinutesAgreesAcrossTheSeam() {
        // The bug this exists to prevent: rounding the half and the
        // within-half position separately could round 359.9° up to a full
        // half (720) *and* keep the half index at 0, producing 0 (midnight)
        // instead of ~720 (noon). Snapping the continuous value in one step
        // must land on the same side of the seam from both directions.
        XCTAssertEqual(DialGeometry.snappedContinuousMinutes(fromContinuousAngle: 359.9), 720)
        XCTAssertEqual(DialGeometry.snappedContinuousMinutes(fromContinuousAngle: 360.1), 720)
        XCTAssertEqual(DialGeometry.snappedContinuousMinutes(fromContinuousAngle: 719.9), 1440)
        XCTAssertEqual(DialGeometry.snappedContinuousMinutes(fromContinuousAngle: 720.1), 1440)
    }

    func testContinuousAngleRoundTripsThroughSnapping() {
        // Re-anchoring a drag at `applied` minutes (continuousAngle) and then
        // re-snapping it (as the next drag frame would) must land back on
        // `applied` exactly, or the drag would silently forget a crossing —
        // or a wall clamp — it already made.
        for minutes in [0, 15, 675, 720, 780, 1425] {
            let angle = DialGeometry.continuousAngle(forMinutes: minutes)
            XCTAssertEqual(DialGeometry.snappedContinuousMinutes(fromContinuousAngle: angle), minutes)
        }
    }
}
