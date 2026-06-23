import SwiftUI
import SwiftData

struct MissedEventsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Event.startTime, order: .reverse) private var allEvents: [Event]

    @State private var rescheduleTitle = ""
    @State private var showingReschedule = false

    private var missedEvents: [Event] {
        allEvents.filter { $0.status == .missed }
    }

    var body: some View {
        ZStack {
            Color.cadenceCream.ignoresSafeArea()

            if missedEvents.isEmpty {
                emptyState
            } else {
                eventList
            }
        }
        .navigationTitle("Missed")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.cadenceCream, for: .navigationBar)
        .sheet(isPresented: $showingReschedule) {
            AddEventView(prefillTitle: rescheduleTitle)
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 52))
                .foregroundColor(.cadenceOrangeLight)
            Text("Nothing missed")
                .font(.headline)
                .foregroundColor(.secondary)
        }
    }

    private var eventList: some View {
        List {
            ForEach(missedEvents) { event in
                EventRowView(event: event)
                    .listRowBackground(Color.cadenceCream)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            reschedule(event)
                        } label: {
                            Label("Reschedule", systemImage: "arrow.clockwise")
                        }
                        .tint(.cadenceOrange)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            context.delete(event)
                            try? context.save()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Actions

    private func reschedule(_ event: Event) {
        rescheduleTitle = event.title
        context.delete(event)
        try? context.save()
        showingReschedule = true
    }
}
