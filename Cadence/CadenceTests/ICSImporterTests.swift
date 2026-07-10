import XCTest
@testable import Cadence

/// ICSImporter is a thin /v1 DTO exchange (calendar-import.md §4): these
/// tests cover request encoding and response decoding via AIService's
/// _callAPI hook. The actual feed fetch + RFC 5545/RRULE expansion is server
/// code, covered by server/test/ics.test.js — not re-tested here.
final class ICSImporterTests: XCTestCase {

    private let emptyResponse = #"{ "events": [], "feedName": null }"#
    private let window = DateInterval(start: Date(timeIntervalSince1970: 1_900_000_000),
                                      duration: 90 * 86_400)

    private func makeImporter(returning json: String, capture: ((String) -> Void)? = nil) -> ICSImporter {
        var api = AIService()
        api._callAPI = { body in
            capture?(body)
            return json
        }
        return ICSImporter(api: api)
    }

    // MARK: - Request encoding

    func testRequestCarriesContractFields() async throws {
        var seenBody: String?
        let importer = makeImporter(returning: emptyResponse) { seenBody = $0 }

        _ = try await importer.importFeed(urlString: "webcal://uni.example.edu/tt.ics", window: window)

        let body = try XCTUnwrap(seenBody)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any]
        )
        // The URL goes up verbatim — webcal normalisation is the server's job.
        XCTAssertEqual(json["url"] as? String, "webcal://uni.example.edu/tt.ics")
        XCTAssertEqual(json["timezone"] as? String, TimeZone.current.identifier)

        // now = full ISO8601 the device formatter can round-trip
        let now = try XCTUnwrap(json["now"] as? String)
        XCTAssertNotNil(AIService.deviceISOFormatter().date(from: now))

        // window bounds as plain yyyy-MM-dd dates
        let dayPattern = #"^\d{4}-\d{2}-\d{2}$"#
        let windowStart = try XCTUnwrap(json["windowStart"] as? String)
        let windowEnd = try XCTUnwrap(json["windowEnd"] as? String)
        XCTAssertNotNil(windowStart.range(of: dayPattern, options: .regularExpression))
        XCTAssertNotNil(windowEnd.range(of: dayPattern, options: .regularExpression))
        XCTAssertNotEqual(windowStart, windowEnd)
    }

    // MARK: - Response decoding

    func testDecodesEventsAndFeedName() async throws {
        let json = """
        { "events": [
            { "title": "Algorithms lecture",
              "start": "2030-06-15T10:00:00+03:00",
              "end": "2030-06-15T12:00:00+03:00",
              "allDay": false,
              "externalIdentifier": "uid-123@uni.edu#2030-06-15T10:00:00+03:00" },
            { "title": "Conference day",
              "start": "2030-06-16T00:00:00+03:00",
              "end": "2030-06-17T00:00:00+03:00",
              "allDay": true,
              "externalIdentifier": "allday-1@test" }
          ],
          "feedName": "Uni Timetable" }
        """
        let importer = makeImporter(returning: json)

        let result = try await importer.importFeed(urlString: "https://x/y.ics", window: window)

        XCTAssertEqual(result.feedName, "Uni Timetable")
        XCTAssertEqual(result.instances.count, 2)

        let lecture = result.instances[0]
        XCTAssertEqual(lecture.title, "Algorithms lecture")
        XCTAssertEqual(lecture.externalIdentifier, "uid-123@uni.edu#2030-06-15T10:00:00+03:00")
        XCTAssertEqual(lecture.categoryHint, "Uni Timetable")
        XCTAssertFalse(lecture.isAllDay)
        // The offset in the payload maps to the right instant (10:00+03:00 == 07:00Z)
        XCTAssertEqual(lecture.start, ISO8601DateFormatter().date(from: "2030-06-15T07:00:00Z"))
        XCTAssertEqual(lecture.end, ISO8601DateFormatter().date(from: "2030-06-15T09:00:00Z"))

        XCTAssertTrue(result.instances[1].isAllDay)
    }

    func testMissingFeedNameFallsBackToImportedHint() async throws {
        let json = """
        { "events": [
            { "title": "One-off", "start": "2030-06-15T10:00:00+03:00",
              "end": "2030-06-15T11:00:00+03:00", "allDay": false,
              "externalIdentifier": "solo@test" }
          ],
          "feedName": null }
        """
        let importer = makeImporter(returning: json)

        let result = try await importer.importFeed(urlString: "https://x/y.ics", window: window)

        XCTAssertNil(result.feedName)
        XCTAssertEqual(result.instances.first?.categoryHint, "Imported")
    }

    func testUndecodableResponseThrowsInvalidResponse() async {
        let importer = makeImporter(returning: "here is prose, not JSON")

        do {
            _ = try await importer.importFeed(urlString: "https://x/y.ics", window: window)
            XCTFail("Expected invalidResponse")
        } catch {
            guard case AIServiceError.invalidResponse = error else {
                return XCTFail("Expected invalidResponse, got \(error)")
            }
        }
    }

    func testBadDateInResponseThrowsInvalidResponse() async {
        let json = """
        { "events": [
            { "title": "Broken", "start": "tomorrow-ish", "end": "later",
              "allDay": false, "externalIdentifier": "x@test" }
          ],
          "feedName": null }
        """
        let importer = makeImporter(returning: json)

        do {
            _ = try await importer.importFeed(urlString: "https://x/y.ics", window: window)
            XCTFail("Expected invalidResponse")
        } catch {
            guard case AIServiceError.invalidResponse = error else {
                return XCTFail("Expected invalidResponse, got \(error)")
            }
        }
    }
}
