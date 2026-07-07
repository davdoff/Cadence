import SwiftUI
import SwiftData

struct TodayView: View {
    @AppStorage("accentColorHex") private var accentColorHex = "#E8784D"
    @Query(sort: \Event.startTime) private var allEvents: [Event]
    @Query private var habits: [Habit]
    @Environment(\.modelContext) private var context
    @AppStorage("greetingName") private var greetingName = ""

    @State private var showingAddEvent = false
    @State private var showingAIInput  = false
    @State private var statusFilter: StatusFilter = .all

    enum StatusFilter: String, CaseIterable {
        case all = "All", pending = "Up Next", done = "Done", missed = "Missed"
        var icon: String {
            switch self {
            case .all:     return "list.bullet"
            case .pending: return "clock.fill"
            case .done:    return "checkmark.circle.fill"
            case .missed:  return "xmark.circle.fill"
            }
        }
        func color(_ accentHex: String) -> Color {
            switch self {
            case .all:     return .appAccent(accentHex)
            case .pending: return .appAccent(accentHex)
            case .done:    return .green
            case .missed:  return .red.opacity(0.75)
            }
        }
    }

    // MARK: - Data

    private var todayEvents: [Event] {
        let start = Calendar.current.startOfDay(for: .now)
        let end   = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        return allEvents.filter { $0.startTime >= start && $0.startTime < end }
    }

    private var filteredEvents: [Event] {
        switch statusFilter {
        case .all:     return todayEvents
        case .pending: return todayEvents.filter { $0.status == .pending  }
        case .done:    return todayEvents.filter { $0.status == .completed }
        case .missed:  return todayEvents.filter { $0.status == .missed   }
        }
    }

    private func eventsIn(_ range: ClosedRange<Int>) -> [Event] {
        filteredEvents.filter { range.contains(Calendar.current.component(.hour, from: $0.startTime)) }
    }

    private var completedToday: Int { todayEvents.filter { $0.status == .completed }.count }
    private var pendingToday:   Int { todayEvents.filter { $0.status == .pending   }.count }
    // Badge for the MissedEventsView tray — displaced events live there too.
    private var missedCount:    Int { allEvents.filter   { $0.status == .missed || $0.status == .displaced }.count }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.appBackground(accentColorHex).ignoresSafeArea()

            VStack(spacing: 0) {
                headerBlock
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 12)

                filterPills
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)

                if todayEvents.isEmpty {
                    emptyState
                } else if filteredEvents.isEmpty {
                    filteredEmpty
                } else {
                    eventList
                }
            }

            addButtons
        }
        .navigationTitle(todayTitle)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.appBackground(accentColorHex), for: .navigationBar)
        .sheet(isPresented: $showingAddEvent) { AddEventView() }
        .sheet(isPresented: $showingAIInput)  { AIInputView()  }
    }

    // MARK: - Header

    private var headerBlock: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(greeting)
                    .font(.headline)
                    .foregroundColor(.primary)

                if !todayEvents.isEmpty {
                    HStack(spacing: 10) {
                        statPill("\(completedToday)/\(todayEvents.count)", icon: "checkmark.circle.fill", color: .green)
                        if pendingToday > 0 {
                            statPill("\(pendingToday) left", icon: "clock.fill", color: .appAccent(accentColorHex))
                        }
                    }
                }
            }

            Spacer()

            NavigationLink { MissedEventsView() } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 22))
                        .foregroundColor(missedCount > 0 ? .appAccent(accentColorHex) : .secondary.opacity(0.4))
                    if missedCount > 0 {
                        Text("\(missedCount)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(3)
                            .background(Color.accentDark(accentColorHex))
                            .clipShape(Circle())
                            .offset(x: 7, y: -7)
                    }
                }
            }
        }
    }

    private func statPill(_ label: String, icon: String, color: Color) -> some View {
        Label(label, systemImage: icon)
            .font(.caption.weight(.medium))
            .foregroundColor(color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.1))
            .clipShape(Capsule())
    }

    // MARK: - Filter pills

    private var filterPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(StatusFilter.allCases, id: \.self) { f in
                    Button {
                        withAnimation(.spring(duration: 0.2)) { statusFilter = f }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: f.icon)
                                .font(.system(size: 11, weight: .semibold))
                            Text(f.rawValue)
                                .font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(statusFilter == f ? f.color(accentColorHex) : Color.appDeep(accentColorHex))
                        .foregroundColor(statusFilter == f ? .white : .secondary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Event list (time-sectioned)

    private var eventList: some View {
        let morning   = eventsIn(0...11)
        let afternoon = eventsIn(12...16)
        let evening   = eventsIn(17...23)
        return List {
            if !morning.isEmpty   { timeSection("Morning",   events: morning)   }
            if !afternoon.isEmpty { timeSection("Afternoon", events: afternoon) }
            if !evening.isEmpty   { timeSection("Evening",   events: evening)   }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .padding(.bottom, 90)
    }

    @ViewBuilder
    private func timeSection(_ label: String, events: [Event]) -> some View {
        Section {
            ForEach(events) { event in
                EventRowView(event: event)
                    .listRowBackground(Color.appBackground(accentColorHex))
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button { mark(event, .completed) } label: {
                            Label("Done", systemImage: "checkmark")
                        }.tint(.green)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button { mark(event, .missed) } label: {
                            Label("Missed", systemImage: "xmark")
                        }.tint(.red)
                    }
            }
        } header: {
            HStack(spacing: 5) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Circle()
                    .fill(Color.accentLight(accentColorHex).opacity(0.6))
                    .frame(width: 5, height: 5)
                Text("\(events.count)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Empty states

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(Color.accentLight(accentColorHex).opacity(0.15)).frame(width: 90, height: 90)
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 40)).foregroundColor(.accentLight(accentColorHex))
            }
            Text("Nothing scheduled today")
                .font(.headline).foregroundColor(.secondary)
            Text("Tap + to add an event or ask AI to schedule one.")
                .font(.subheadline).foregroundColor(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filteredEmpty: some View {
        VStack(spacing: 12) {
            Image(systemName: statusFilter.icon)
                .font(.system(size: 40)).foregroundColor(statusFilter.color(accentColorHex).opacity(0.4))
            Text("No \(statusFilter.rawValue.lowercased()) events today")
                .font(.subheadline).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - FAB buttons

    private var addButtons: some View {
        HStack(spacing: 12) {
            Button { showingAIInput = true } label: {
                Label("Ask AI", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.appAccent(accentColorHex))
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(Color.appDeep(accentColorHex))
                    .clipShape(Capsule())
            }
            Button { showingAddEvent = true } label: {
                Label("Add Event", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(Color.appAccent(accentColorHex))
                    .clipShape(Capsule())
            }
        }
        .padding(.bottom, 24)
        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
    }

    // MARK: - Helpers

    private func mark(_ event: Event, _ status: EventStatus) {
        let svc = NotificationService()
        event.status = status
        svc.cancelEventNotifications(for: event)
        if status == .completed, let cat = event.category?.name {
            for habit in habits where habit.correlatedCategoryName?.lowercased() == cat.lowercased() {
                habit.increment()
            }
        } else if status == .missed {
            svc.scheduleReschedulingNudge(for: event, after: 2)
        }
        try? context.save()
        WidgetSync.refresh()
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let base = hour < 12 ? "Good morning" : hour < 17 ? "Good afternoon" : "Good evening"
        return greetingName.trimmingCharacters(in: .whitespaces).isEmpty
            ? "\(base)!"
            : "\(base), \(greetingName.trimmingCharacters(in: .whitespaces))!"
    }

    private var todayTitle: String {
        let f = DateFormatter(); f.dateFormat = "EEEE, MMM d"
        return f.string(from: .now)
    }
}
