import Foundation
import SwiftData

/// Bulk category assignment for one-off events that share a title — the
/// "set the category on every 'Standup' at once" action from the edit sheet.
/// Pure OS-blind decision logic (title match + assignment); the caller owns
/// saving and any widget refresh. Recurring series are handled by
/// `RecurrenceService`, not here.
enum EventBulkService {

    /// Case-insensitive, whitespace-trimmed title key used for grouping.
    private static func key(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// Sets `category` on every event whose title matches `title`
    /// (case-insensitive). Returns how many events actually changed.
    @MainActor
    @discardableResult
    static func setCategory(
        _ category: Category?,
        forEventsTitled title: String,
        context: ModelContext
    ) -> Int {
        let target = key(title)
        guard !target.isEmpty else { return 0 }
        let all = (try? context.fetch(FetchDescriptor<Event>())) ?? []
        var changed = 0
        for event in all where key(event.title) == target {
            if event.category?.id != category?.id {
                event.category = category
                changed += 1
            }
        }
        return changed
    }

    /// Number of OTHER events sharing `event`'s title — drives whether the edit
    /// sheet offers the bulk-category toggle for a non-recurring event.
    @MainActor
    static func siblingCount(of event: Event, context: ModelContext) -> Int {
        let target = key(event.title)
        guard !target.isEmpty else { return 0 }
        let all = (try? context.fetch(FetchDescriptor<Event>())) ?? []
        return all.filter { $0.id != event.id && key($0.title) == target }.count
    }
}
