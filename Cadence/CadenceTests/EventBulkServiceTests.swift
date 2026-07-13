import XCTest
import SwiftData
@testable import Cadence

/// Covers the one-off "set the category on every event named X" bulk action
/// (case-insensitive title grouping, self-exclusion for the sibling count).
@MainActor
final class EventBulkServiceTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext!

    override func setUp() {
        super.setUp()
        let schema = Schema([Event.self, EventSeries.self, Cadence.Category.self, UserPreferences.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: schema, configurations: config)
        context = ModelContext(container)
    }

    override func tearDown() {
        container = nil
        context = nil
        super.tearDown()
    }

    @discardableResult
    private func makeEvent(_ title: String, category: Category? = nil) -> Event {
        let e = Event(title: title,
                      startTime: .now,
                      endTime: .now.addingTimeInterval(3600),
                      category: category)
        context.insert(e)
        return e
    }

    func testSetCategoryUpdatesEveryMatchingTitleCaseInsensitively() {
        let fitness = Category(name: "Fitness", colorHex: "#FF0000")
        context.insert(fitness)
        makeEvent("Gym")
        makeEvent("gym")
        makeEvent("GYM ")            // trailing space still matches
        makeEvent("Standup")        // unrelated, must stay untouched

        let changed = EventBulkService.setCategory(fitness, forEventsTitled: "Gym", context: context)

        XCTAssertEqual(changed, 3)
        let all = (try? context.fetch(FetchDescriptor<Event>())) ?? []
        for e in all where e.title.trimmingCharacters(in: .whitespaces).lowercased() == "gym" {
            XCTAssertEqual(e.category?.id, fitness.id)
        }
        for e in all where e.title == "Standup" {
            XCTAssertNil(e.category)
        }
    }

    func testSetCategoryCountsOnlyActualChanges() {
        let fitness = Category(name: "Fitness", colorHex: "#FF0000")
        context.insert(fitness)
        makeEvent("Gym", category: fitness)   // already Fitness — no change
        makeEvent("Gym")                       // will change

        let changed = EventBulkService.setCategory(fitness, forEventsTitled: "Gym", context: context)
        XCTAssertEqual(changed, 1)
    }

    func testSetCategoryCanClearToNil() {
        let fitness = Category(name: "Fitness", colorHex: "#FF0000")
        context.insert(fitness)
        makeEvent("Gym", category: fitness)
        makeEvent("Gym", category: fitness)

        let changed = EventBulkService.setCategory(nil, forEventsTitled: "Gym", context: context)
        XCTAssertEqual(changed, 2)
    }

    func testSiblingCountExcludesSelfAndNonMatching() {
        let target = makeEvent("Gym")
        makeEvent("gym")
        makeEvent("GYM")
        makeEvent("Standup")

        XCTAssertEqual(EventBulkService.siblingCount(of: target, context: context), 2)
    }

    func testSiblingCountIsZeroForUniqueTitle() {
        let target = makeEvent("Dentist")
        makeEvent("Gym")

        XCTAssertEqual(EventBulkService.siblingCount(of: target, context: context), 0)
    }
}
