import Foundation

/// Thin client for POST /v1/calendar/ics (calendar-import.md §4.0, §4.3):
/// sends the feed URL + expansion window, decodes the returned event DTOs
/// into ImportedEventInstance values for CalendarImportService's shared
/// dedupe pass. The server owns fetching and RFC 5545/RRULE expansion — no
/// Claude call is involved. Never touches EventKit, SwiftData contexts, or
/// notifications; plain value types only.
struct ICSImporter {

    /// Rides on AIService's /v1 plumbing: uniform error-envelope handling
    /// (BAD_REQUEST/TIMEOUT → serverError) and the _callAPI test hook.
    var api = AIService()

    struct FeedResult {
        let feedName: String?
        let instances: [ImportedEventInstance]
    }

    func importFeed(urlString: String, window: DateInterval) async throws -> FeedResult {
        struct Request: Encodable {
            let url: String
            let now: String
            let timezone: String
            let windowStart: String
            let windowEnd: String
        }
        struct Response: Decodable {
            struct Item: Decodable {
                let title: String
                let start: String
                let end: String
                let allDay: Bool
                let externalIdentifier: String
                let seriesIdentifier: String?
            }
            let events: [Item]
            let feedName: String?
        }

        let iso = AIService.deviceISOFormatter()
        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "yyyy-MM-dd"
        dayFmt.locale = Locale(identifier: "en_US_POSIX")

        let body = try JSONEncoder().encode(Request(
            url: urlString,
            now: iso.string(from: .now),
            timezone: TimeZone.current.identifier,
            windowStart: dayFmt.string(from: window.start),
            windowEnd: dayFmt.string(from: window.end)
        ))
        let data = try await api.exchange(route: "/v1/calendar/ics", body: body)

        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw AIServiceError.invalidResponse
        }
        let instances = try response.events.map { item in
            guard let start = iso.date(from: item.start), let end = iso.date(from: item.end) else {
                throw AIServiceError.invalidResponse
            }
            return ImportedEventInstance(
                title: item.title,
                start: start,
                end: end,
                isAllDay: item.allDay,
                externalIdentifier: item.externalIdentifier,
                categoryHint: response.feedName ?? "Imported",
                seriesIdentifier: item.seriesIdentifier
            )
        }
        return FeedResult(feedName: response.feedName, instances: instances)
    }
}
