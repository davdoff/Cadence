import XCTest
import SwiftData
@testable import Cadence

/// Covers the shared dedupe pass's handling of source-owned location/notes
/// (CADENCE_README §1.1b): backfill onto events imported before the fields
/// existed, no duplicates, status/category untouched, and no write at all
/// when nothing changed at the source.
@MainActor
final class CalendarImportServiceTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext!
    var source: CalendarImportSource!
    var prefs: UserPreferences!

    private let window = DateInterval(start: .now, duration: 90 * 86_400)
    private lazy var start = Date.now.addingTimeInterval(86_400)
    private lazy var end = start.addingTimeInterval(7_200)

    override func setUp() {
        super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: SharedModelContainer.schema, configurations: config)
        context = ModelContext(container)
        source = CalendarImportSource(kind: .deviceCalendar, displayName: "Uni", identifier: "cal-uni")
        context.insert(source)
        // Notifications off: the pass must not reach UNUserNotificationCenter.
        prefs = UserPreferences()
        prefs.notificationsEnabled = false
        context.insert(prefs)
    }

    override func tearDown() {
        container = nil
        context = nil
        source = nil
        prefs = nil
        super.tearDown()
    }

    private func instance(location: String?, notes: String?) -> ImportedEventInstance {
        ImportedEventInstance(
            title: "Algorithms lecture",
            start: start,
            end: end,
            isAllDay: false,
            externalIdentifier: "ext-1",
            categoryHint: "Some other calendar",
            seriesIdentifier: nil,
            location: location,
            notes: notes
        )
    }

    /// An event as imported before location/notes existed: both nil.
    @discardableResult
    private func makeLegacyImport(status: EventStatus = .pending, category: Cadence.Category? = nil) -> Event {
        let event = Event(title: "Algorithms lecture", startTime: start, endTime: end,
                          category: category, source: .imported,
                          externalIdentifier: "ext-1", importSourceID: source.identifier)
        event.status = status
        context.insert(event)
        try! context.save()
        return event
    }

    private func apply(_ instances: [ImportedEventInstance]) -> Bool {
        CalendarImportService.shared.apply(instances, to: source, window: window, prefs: prefs, context: context)
    }

    private func allEvents() -> [Event] {
        (try? context.fetch(FetchDescriptor<Event>())) ?? []
    }

    // MARK: - Re-sync

    func testResyncBackfillsLocationAndNotesWithoutDuplicating() {
        let uni = Cadence.Category(name: "Uni", colorHex: "#3366FF")
        context.insert(uni)
        let event = makeLegacyImport(status: .completed, category: uni)
        XCTAssertNil(event.location)

        let changed = apply([instance(location: "Room 2A-04, Main Building", notes: "Bring a laptop")])

        XCTAssertTrue(changed)
        XCTAssertEqual(allEvents().count, 1, "matched by externalIdentifier — no duplicate")
        XCTAssertEqual(event.location, "Room 2A-04, Main Building")
        XCTAssertEqual(event.notes, "Bring a laptop")
        // Only the source-owned fields moved.
        XCTAssertEqual(event.status, .completed)
        XCTAssertEqual(event.category?.id, uni.id)
    }

    func testSourceClearingLocationClearsItLocally() {
        let event = makeLegacyImport()
        _ = apply([instance(location: "Room 1", notes: "Old notes")])
        try! context.save()

        XCTAssertTrue(apply([instance(location: nil, notes: nil)]))
        XCTAssertNil(event.location)
        XCTAssertNil(event.notes)
    }

    func testUnchangedSourceWritesNothing() {
        makeLegacyImport()
        XCTAssertTrue(apply([instance(location: "Room 1", notes: "Notes")]))
        try! context.save()

        let changed = apply([instance(location: "Room 1", notes: "Notes")])

        XCTAssertFalse(changed, "no change → no save, no widget reload")
        XCTAssertFalse(context.hasChanges, "an unchanged event must not even be dirtied")
    }

    func testFreshImportCarriesLocationAndNotes() {
        XCTAssertTrue(apply([instance(location: "Lab B", notes: "https://zoom.us/j/123")]))

        let events = allEvents()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.location, "Lab B")
        XCTAssertEqual(events.first?.notes, "https://zoom.us/j/123")
    }

    // MARK: - Source text normalisation (shared by EventKit + ICS mapping)

    func testSourceTextTrimsAndBlankBecomesNil() {
        XCTAssertNil(ImportedEventInstance.sourceText(nil))
        XCTAssertNil(ImportedEventInstance.sourceText(""))
        XCTAssertNil(ImportedEventInstance.sourceText("  \n\t \n"), "blank EventKit notes → nil")
        XCTAssertEqual(ImportedEventInstance.sourceText("  Room 1 \n"), "Room 1")
        // Inner newlines are content, not padding.
        XCTAssertEqual(ImportedEventInstance.sourceText("Line1\nLine2\n"), "Line1\nLine2")
    }

    // MARK: - Detail view helpers

    func testMapsURLPercentEncodesTheWholeLocation() {
        let url = EventDetailView.mapsURL(for: "Room 2A-04, Main Building & Annex #3")
        XCTAssertEqual(url?.absoluteString,
                       "https://maps.apple.com/?q=Room%202A-04%2C%20Main%20Building%20%26%20Annex%20%233")
    }
}
