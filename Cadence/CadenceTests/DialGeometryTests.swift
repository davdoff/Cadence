import XCTest
@testable import Cadence

final class DialGeometryTests: XCTestCase {

    // MARK: - Angle ↔ minutes mapping (720° = 24 h, 1° = 2 min)

    func testTotalAngleFromMinutes() {
        XCTAssertEqual(DialGeometry.totalAngle(fromMinutes: 0), 0)          // midnight
        XCTAssertEqual(DialGeometry.totalAngle(fromMinutes: 540), 270)      // 9:00 AM
        XCTAssertEqual(DialGeometry.totalAngle(fromMinutes: 720), 360)      // noon = end of lap 0
        XCTAssertEqual(DialGeometry.totalAngle(fromMinutes: 1260), 630)     // 9:00 PM, lap 1
        XCTAssertEqual(DialGeometry.totalAngle(fromMinutes: 1440), 720)     // full day
    }

    func testMinutesFromTotalAngleRoundTrips() {
        for minutes in stride(from: 0, through: 1440, by: 15) {
            let angle = DialGeometry.totalAngle(fromMinutes: minutes)
            XCTAssertEqual(DialGeometry.minutes(fromTotalAngle: angle), minutes)
        }
    }

    // MARK: - Face angle (12-hour face, AM/PM ambiguity by design)

    func testFaceAngleSharedBetweenLaps() {
        XCTAssertEqual(DialGeometry.faceAngle(forMinutes: 540), 270)   // 9:00 AM
        XCTAssertEqual(DialGeometry.faceAngle(forMinutes: 1260), 270)  // 9:00 PM → same face
        XCTAssertEqual(DialGeometry.faceAngle(forMinutes: 720), 0)     // noon points at 12
        XCTAssertEqual(DialGeometry.faceAngle(forMinutes: 180), 90)    // 3:00 AM points at 3
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
}
