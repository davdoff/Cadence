import SwiftUI
import SwiftData

struct MissedEventsView: View {
    @AppStorage("accentColorHex") private var accentColorHex = "#E8784D"
    @Environment(\.modelContext) private var context
    @Query(sort: \Event.startTime, order: .reverse) private var allEvents: [Event]

    @State private var rescheduleTitle = ""
    @State private var showingReschedule = false

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
            Color.appBackground(accentColorHex).ignoresSafeArea()

            if missedEvents.isEmpty && displacedEvents.isEmpty {
                emptyState
            } else {
                eventList
            }
        }
        .navigationTitle("Missed")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.appBackground(accentColorHex), for: .navigationBar)
        .sheet(isPresented: $showingReschedule) {
            AddEventView(prefillTitle: rescheduleTitle)
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 52))
                .foregroundColor(.accentLight(accentColorHex))
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
            .listRowBackground(Color.appBackground(accentColorHex))
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    reschedule(event)
                } label: {
                    Label("Reschedule", systemImage: "arrow.clockwise")
                }
                .tint(.appAccent(accentColorHex))
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    context.delete(event)
                    try? context.save()
                    WidgetSync.refresh()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }

    // MARK: - Actions

    private func reschedule(_ event: Event) {
        rescheduleTitle = event.title
        context.delete(event)
        try? context.save()
        WidgetSync.refresh()
        showingReschedule = true
    }
}
