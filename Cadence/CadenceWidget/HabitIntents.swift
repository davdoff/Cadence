import AppIntents
import SwiftData
import WidgetKit

// MARK: - Habit entity (widget configuration)

struct HabitEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Habit"
    static let defaultQuery = HabitEntityQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct HabitEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [HabitEntity] {
        allEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [HabitEntity] {
        allEntities()
    }

    func defaultResult() async -> HabitEntity? {
        allEntities().first
    }

    private func allEntities() -> [HabitEntity] {
        WidgetDataStore.allHabits().map { HabitEntity(id: $0.id, name: $0.name) }
    }
}

// MARK: - Widget configuration intents

struct SelectHabitIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Habit"
    static let description = IntentDescription("Choose which habit this widget shows.")

    @Parameter(title: "Habit")
    var habit: HabitEntity?
}

struct SelectHabitsIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Habits"
    static let description = IntentDescription("Choose up to four habits to show.")

    @Parameter(title: "Habits", size: 4)
    var habits: [HabitEntity]?
}

// MARK: - Increment intent (interactive + button)

/// Runs in the widget process: writes +1 to the shared App Group store,
/// then reloads all timelines so every habit widget shows the new count.
struct IncrementHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Habit"
    static let description = IntentDescription("Adds one to today's count for a habit.")

    @Parameter(title: "Habit ID")
    var habitID: String

    init() {}

    init(habitID: UUID) {
        self.habitID = habitID.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: habitID) else { return .result() }
        let context = ModelContext(WidgetDataStore.container)
        let descriptor = FetchDescriptor<Habit>(predicate: #Predicate { $0.id == id })
        if let habit = try context.fetch(descriptor).first {
            habit.increment()
            try context.save()
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
