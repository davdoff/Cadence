import SwiftUI
import SwiftData

struct MissedEventsView: View {
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var context
    @Query(sort: \Event.startTime, order: .reverse) private var allEvents: [Event]

    @State private var reschedulingEvent: Event?

    private var missedEvents: [Event] {
        allEvents.filter { $0.status == .missed }
    }

    // "Needs rescheduling" tray (ai-planner.md §6): events the planner moved
    // aside during a reorganize — not failures, just waiting for a new slot.
    private var displacedEvents: [Event] {
        allEvents.filter { $0.status == .displaced }
    }

    var body: some View {
        ZStack {
            theme.backgroundGradient.ignoresSafeArea()

            if missedEvents.isEmpty && displacedEvents.isEmpty {
                emptyState
            } else {
                eventList
            }
        }
        .navigationTitle("Missed")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(theme.background, for: .navigationBar)
        // The original stays put until the replacement is saved — cancelling
        // the sheet loses nothing (UI_REVIEW §1.2).
        .sheet(item: $reschedulingEvent) { event in
            AddEventView(reschedulingSource: event)
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 52))
                .foregroundColor(theme.light)
            Text("Nothing missed")
                .font(.headline)
                .foregroundColor(.secondary)
        }
    }

    private var eventList: some View {
        List {
            if !displacedEvents.isEmpty {
                Section {
                    ForEach(displacedEvents) { event in
                        eventRow(event)
                    }
                } header: {
                    Label("Needs rescheduling", systemImage: "arrow.uturn.right.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.orange)
                }
            }

            if !missedEvents.isEmpty {
                Section {
                    ForEach(missedEvents) { event in
                        eventRow(event)
                    }
                } header: {
                    if !displacedEvents.isEmpty {
                        Label("Missed", systemImage: "exclamationmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.red.opacity(0.7))
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func eventRow(_ event: Event) -> some View {
        EventRowView(event: event)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    reschedulingEvent = event
                } label: {
                    Label("Reschedule", systemImage: "arrow.clockwise")
                }
                .tint(theme.accent)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    // Imported events: tombstone so the next sync doesn't re-insert it.
                    CalendarImportService.shared.noteLocalDeletion(of: event, context: context)
                    context.delete(event)
                    try? context.save()
                    WidgetSync.refresh()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }
}
