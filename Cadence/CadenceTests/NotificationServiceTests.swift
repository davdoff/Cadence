import XCTest
import SwiftData
@testable import Cadence

final class NotificationServiceTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext!
    let service = NotificationService()

    override func setUp() {
        super.setUp()
        let schema = Schema([Event.self, Cadence.Category.self, Meal.self, UserPreferences.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: schema, configurations: config)
        context = ModelContext(container)
    }

    override func tearDown() {
        container = nil
        context = nil
        super.tearDown()
    }

    // MARK: - Helpers

    func makePrefs(enabled: Bool = true) -> UserPreferences {
        let p = UserPreferences()
        p.notificationsEnabled = enabled
        context.insert(p)
        return p
    }

    func makeCategory(name: String = "Work") -> Cadence.Category {
        let c = Cadence.Category(name: name, colorHex: "#FF0000")
        context.insert(c)
        return c
    }

    func makeEvent(title: String = "Meeting", withCategory: Cadence.Category? = nil) -> Event {
        let start = Date().addingTimeInterval(3600)
        let end = start.addingTimeInterval(3600)
        let e = Event(title: title, startTime: start, endTime: end, category: withCategory)
        context.insert(e)
        return e
    }

    // MARK: - isNotificationEnabled

    func testNotificationsGloballyDisabledReturnsFalse() {
        let prefs = makePrefs(enabled: false)
        let event = makeEvent()
        XCTAssertFalse(service.isNotificationEnabled(for: event, prefs: prefs))
    }

    func testNotificationsEnabledEventWithNoCategory() {
        // No category → default to enabled
        let prefs = makePrefs(enabled: true)
        let event = makeEvent(withCategory: nil)
        XCTAssertTrue(service.isNotificationEnabled(for: event, prefs: prefs))
    }

    func testNotificationsEnabledCategoryWithNoOverride() {
        // Category exists but no per-category entry → default to enabled
        let prefs = makePrefs(enabled: true)
        let cat = makeCategory()
        let event = makeEvent(withCategory: cat)
        // perCategoryNotifications is empty — no override for this category
        XCTAssertTrue(service.isNotificationEnabled(for: event, prefs: prefs))
    }

    func testNotificationsEnabledForSpecificCategory() {
        let prefs = makePrefs(enabled: true)
        let cat = makeCategory()
        let event = makeEvent(withCategory: cat)
        prefs.setPerCategoryNotifications([cat.id: true])
        XCTAssertTrue(service.isNotificationEnabled(for: event, prefs: prefs))
    }

    func testNotificationsDisabledForSpecificCategory() {
        let prefs = makePrefs(enabled: true)
        let cat = makeCategory()
        let event = makeEvent(withCategory: cat)
        prefs.setPerCategoryNotifications([cat.id: false])
        XCTAssertFalse(service.isNotificationEnabled(for: event, prefs: prefs))
    }

    func testGlobalDisabledOverridesCategoryEnabled() {
        // Global off + category explicitly enabled → still false
        let prefs = makePrefs(enabled: false)
        let cat = makeCategory()
        let event = makeEvent(withCategory: cat)
        prefs.setPerCategoryNotifications([cat.id: true])
        XCTAssertFalse(service.isNotificationEnabled(for: event, prefs: prefs))
    }

    // MARK: - Identifier format

    func testEventReminderIdentifierFollowsPattern() {
        // Past event: the guard fires early (no real notification added),
        // but the identifier is still returned with the correct format.
        let past = Date().addingTimeInterval(-7200)
        let event = Event(title: "Old Meeting", startTime: past, endTime: past.addingTimeInterval(3600))
        context.insert(event)

        let identifier = service.scheduleEventReminder(for: event, reminderMinutes: 15)
        XCTAssertEqual(identifier, "event-reminder-\(event.id.uuidString)")
    }

    func testEventStartAlertIdentifierFollowsPattern() {
        // Past event: the guard fires early, but the identifier keeps its format.
        let past = Date().addingTimeInterval(-7200)
        let event = Event(title: "Old Meeting", startTime: past, endTime: past.addingTimeInterval(3600))
        context.insert(event)

        let identifier = service.scheduleEventStartAlert(for: event, reminderMinutes: 15)
        XCTAssertEqual(identifier, "event-start-\(event.id.uuidString)")
    }

    func testEventStartAlertZeroReminderStillReturnsIdentifier() {
        // reminderMinutes == 0 → skipped (the reminder already fires at start),
        // but the identifier is still returned for cancellation symmetry.
        let event = makeEvent()
        let identifier = service.scheduleEventStartAlert(for: event, reminderMinutes: 0)
        XCTAssertEqual(identifier, "event-start-\(event.id.uuidString)")
    }

    func testMealNotificationIdentifierFollowsPattern() {
        let past = Date().addingTimeInterval(-7200)
        let event = Event(title: "Dinner", startTime: past, endTime: past.addingTimeInterval(3600))
        context.insert(event)

        let identifier = service.scheduleMealNotification(for: event, reminderMinutes: 15)
        XCTAssertEqual(identifier, "meal-\(event.id.uuidString)")
    }

    func testEachEventGetsUniqueIdentifier() {
        let past = Date().addingTimeInterval(-7200)
        let e1 = Event(title: "A", startTime: past, endTime: past.addingTimeInterval(3600))
        let e2 = Event(title: "B", startTime: past, endTime: past.addingTimeInterval(3600))
        context.insert(e1)
        context.insert(e2)

        let id1 = service.scheduleEventReminder(for: e1, reminderMinutes: 15)
        let id2 = service.scheduleEventReminder(for: e2, reminderMinutes: 15)
        XCTAssertNotEqual(id1, id2)
    }

    // MARK: - perCategoryNotifications round-trip

    func testPerCategoryNotificationsRoundTrip() {
        let prefs = makePrefs()
        let catID = UUID()
        prefs.setPerCategoryNotifications([catID: false])
        let decoded = prefs.perCategoryNotifications()
        XCTAssertEqual(decoded[catID], false)
    }

    func testPerCategoryNotificationsEmptyByDefault() {
        let prefs = makePrefs()
        XCTAssertTrue(prefs.perCategoryNotifications().isEmpty)
    }
}
