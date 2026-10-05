import XCTest
@testable import Cadence

/// ICSImporter is a thin /v1 DTO exchange (CADENCE_README §1.1a): these
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
              "externalIdentifier": "uid-123@uni.edu#2030-06-15T10:00:00+03:00",
              "seriesIdentifier": "uid-123@uni.edu" },
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
        // Recurring occurrences carry the shared base UID for series grouping.
        XCTAssertEqual(lecture.seriesIdentifier, "uid-123@uni.edu")
        // The offset in the payload maps to the right instant (10:00+03:00 == 07:00Z)
        XCTAssertEqual(lecture.start, ISO8601DateFormatter().date(from: "2030-06-15T07:00:00Z"))
        XCTAssertEqual(lecture.end, ISO8601DateFormatter().date(from: "2030-06-15T09:00:00Z"))

        XCTAssertTrue(result.instances[1].isAllDay)
        // One-off events (and older payloads without the key) decode to nil.
        XCTAssertNil(result.instances[1].seriesIdentifier)
    }

    func testDecodesLocationAndNotesAndToleratesTheirAbsence() async throws {
        // Unescaping is the server's job (server/test/ics.test.js); the client
        // only trims and maps blank → nil. The second item omits both keys,
        // as an older server would.
        let json = """
        { "events": [
            { "title": "Databases lab", "start": "2030-06-15T10:00:00+03:00",
              "end": "2030-06-15T12:00:00+03:00", "allDay": false,
              "externalIdentifier": "lab@test",
              "location": "Room 2A-04, Main Building",
              "notes": "Lecturer: Dr. Popescu\\nBring a laptop" },
            { "title": "Old server", "start": "2030-06-16T10:00:00+03:00",
              "end": "2030-06-16T11:00:00+03:00", "allDay": false,
              "externalIdentifier": "old@test" },
            { "title": "Blank", "start": "2030-06-17T10:00:00+03:00",
              "end": "2030-06-17T11:00:00+03:00", "allDay": false,
              "externalIdentifier": "blank@test",
              "location": "   ", "notes": null }
          ],
          "feedName": null }
        """
        let importer = makeImporter(returning: json)

        let result = try await importer.importFeed(urlString: "https://x/y.ics", window: window)

        XCTAssertEqual(result.instances[0].location, "Room 2A-04, Main Building")
        XCTAssertEqual(result.instances[0].notes, "Lecturer: Dr. Popescu\nBring a laptop")
        XCTAssertNil(result.instances[1].location)
        XCTAssertNil(result.instances[1].notes)
        XCTAssertNil(result.instances[2].location, "whitespace-only → nil")
        XCTAssertNil(result.instances[2].notes)
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
