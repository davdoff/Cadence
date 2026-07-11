import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.theme) private var theme
    @Query(sort: \Event.startTime) private var allEvents: [Event]
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("greetingName") private var greetingName = ""

    @State private var showingAddEvent = false
    @State private var showingAIInput  = false
    @State private var statusFilter: StatusFilter = .all
    // Which pending event has its "Start" pill revealed (only one at a time).
    @State private var revealedEventID: UUID?

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
        func color(_ theme: Theme) -> Color {
            switch self {
            case .all:     return theme.accent
            case .pending: return theme.accent
            case .done:    return .green
            case .missed:  return .red.opacity(0.75)
            }
        }
        /// Selected-pill fill (§4): the accent `pill` gradient for accent-colored
        /// filters, flat semantic color for the green/red ones.
        func fill(_ theme: Theme) -> AnyShapeStyle {
            switch self {
            case .all, .pending: return AnyShapeStyle(theme.pillGradient)
            case .done, .missed: return AnyShapeStyle(color(theme))
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
        // "All" is the working set — completed events live only under "Done".
        case .all:     return todayEvents.filter { $0.status != .completed }
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
        ZStack {
            theme.backgroundGradient.ignoresSafeArea()
                // Tapping off a row collapses any revealed Start/Stop pill.
                .onTapGesture { revealedEventID = nil }

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
        }
        // Inset instead of a hard-coded bottom padding, so the list scrolls
        // clear of the buttons on every device.
        .safeAreaInset(edge: .bottom) { addButtons }
        .navigationTitle(todayTitle)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(theme.background, for: .navigationBar)
        .sheet(isPresented: $showingAddEvent) { AddEventView() }
        .sheet(isPresented: $showingAIInput)  { AIInputView()  }
        // Complete any started events whose timer elapsed while we weren't
        // watching (app backgrounded / closed).
        .onAppear { completeElapsedRunningEvents() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { completeElapsedRunningEvents() }
        }
    }

    // MARK: - Header

    private var headerBlock: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(greeting)
                    .font(.cadHeadline)
                    .foregroundColor(.primary)

                if !todayEvents.isEmpty {
                    HStack(spacing: 10) {
                        statPill("\(completedToday)/\(todayEvents.count)", icon: "checkmark.circle.fill", color: .green)
                        if pendingToday > 0 {
                            statPill("\(pendingToday) left", icon: "clock.fill", color: theme.accent)
                        }
                    }
                }
            }

            Spacer()

            NavigationLink { MissedEventsView() } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 22))
                        .foregroundColor(missedCount > 0 ? theme.accent : .secondary.opacity(0.4))
                    if missedCount > 0 {
                        Text("\(missedCount)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(3)
                            .background(theme.dark)
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
        // Centered rather than flush-left; sizes unchanged. Four short pills fit
        // without scrolling, so `.frame(maxWidth: .infinity)` centers the group.
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
                    .background(statusFilter == f ? f.fill(theme) : AnyShapeStyle(theme.chipBg))
                    .foregroundColor(statusFilter == f ? .white : theme.chipText)
                    .clipShape(Capsule())
                    // Active pill glows in its own hue (§4 pill-glow).
                    .shadow(color: statusFilter == f ? f.color(theme).opacity(0.45) : .clear,
                            radius: 6, y: 2)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
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
    }

    @ViewBuilder
    private func timeSection(_ label: String, events: [Event]) -> some View {
        Section {
            ForEach(events) { event in
                StartableEventRow(
                    event: event,
                    isRevealed: revealedEventID == event.id,
                    onToggle: { toggleReveal(event) },
                    onStart:  { start(event) },
                    onStop:   { stop(event) },
                    onFinish: { complete(event) }
                )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if event.status == .completed {
                            // Swiping "complete" on an already-done event undoes it.
                            Button { uncomplete(event) } label: {
                                Label("Undo", systemImage: "arrow.uturn.left")
                            }.tint(.orange)
                        } else {
                            Button { mark(event, .completed) } label: {
                                Label("Done", systemImage: "checkmark")
                            }.tint(.green)
                        }
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
                    .fill(theme.light.opacity(0.6))
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
                Circle().fill(theme.emptyOrb).frame(width: 90, height: 90)
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 40)).foregroundColor(theme.accent)
            }
            Text("Nothing scheduled today")
                .font(.cadHeadline).foregroundColor(.secondary)
            Text("Tap + to add an event or ask AI to schedule one.")
                .font(.subheadline).foregroundColor(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filteredEmpty: some View {
        VStack(spacing: 12) {
            Image(systemName: statusFilter.icon)
                .font(.system(size: 40)).foregroundColor(statusFilter.color(theme).opacity(0.4))
            Text("No \(statusFilter.rawValue.lowercased()) events today")
                .font(.subheadline).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - FAB buttons

    private var addButtons: some View {
        HStack(spacing: 14) {
            // "Ask AI" — lighter/outlined variant of the pill family (§4).
            Button { showingAIInput = true } label: {
                Label("Ask AI", systemImage: "sparkles")
                    .font(.cadBodyStrong)
                    .foregroundColor(theme.accent)
                    .padding(.horizontal, 26).padding(.vertical, 16)
                    .background(theme.chipBg)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(theme.accent.opacity(0.4), lineWidth: 1.5))
            }
            // "Add Event" — filled pill gradient + colored glow (§4).
            Button { showingAddEvent = true } label: {
                Label("Add Event", systemImage: "plus")
                    .font(.cadBodyStrong)
                    .foregroundColor(.white)
                    .padding(.horizontal, 26).padding(.vertical, 16)
                    .background(theme.pillGradient)
                    .clipShape(Capsule())
                    .shadow(color: theme.pillGlow, radius: 12, y: 5)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 20)
    }

    // MARK: - Helpers

    /// Marks the event as started: stamps `startedAt`, schedules the
    /// "time's up" notification, and collapses the reveal. Status stays
    /// `.pending` — the user still marks done/missed when finished.
    /// Tap on a row: reveal (or hide) its Start/Stop affordance. Completed rows
    /// aren't actionable, so they ignore the tap.
    private func toggleReveal(_ event: Event) {
        guard event.isRunning || event.canStart else { return }
        revealedEventID = (revealedEventID == event.id) ? nil : event.id
    }

    private func start(_ event: Event) {
        EventActionService.start(event, context: context)
        revealedEventID = nil
    }

    /// Stop a running event's timer: cancel the run and revert to pending (an
    /// undo for an accidental Start) — completion is done by swiping, not here.
    private func stop(_ event: Event) {
        revealedEventID = nil
        EventActionService.cancelTimer(event, context: context)
    }

    /// Undo a completion (swipe-right on a done event): revert to pending and
    /// roll back the correlated habit increment.
    private func uncomplete(_ event: Event) {
        EventActionService.revertToPending(event, context: context)
    }

    /// Auto-completes a running event when its timer ends (reuses the
    /// swipe-to-done path). Guarded so the finish-`.task` and the scenePhase
    /// reconciliation can't complete the same event twice.
    private func complete(_ event: Event) {
        guard event.isRunning else { return }
        mark(event, .completed)
    }

    /// Completes any started event whose countdown already elapsed while the
    /// app wasn't foreground. Runs on appear and when the app becomes active.
    private func completeElapsedRunningEvents() {
        let now = Date.now
        for event in allEvents where event.isRunning {
            if let finish = event.finishTime, finish <= now { mark(event, .completed) }
        }
    }

    private func mark(_ event: Event, _ status: EventStatus) {
        switch status {
        case .completed: EventActionService.complete(event, context: context)
        case .missed:    EventActionService.miss(event, context: context)
        default:         break
        }
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

// MARK: - Startable row

/// Today's event row with the tap-to-start affordance. Tapping a startable event
/// springs the card narrower and reveals a "Start" pill; tapping Start swaps it
/// for a live countdown that auto-completes when it hits zero. Tapping a running
/// event reveals a "Stop" pill in place of the timer. The trailing area is an
/// animatable fixed-width slot, so the card shrinks *as* the pill widens — one
/// layout change, not a pop-in. (Detail is intentionally not wired here.)
private struct StartableEventRow: View {
    @Environment(\.theme) private var theme
    let event: Event
    let isRevealed: Bool
    let onToggle: () -> Void
    let onStart: () -> Void
    let onStop: () -> Void
    let onFinish: () -> Void

    /// Width of the trailing pill/timer slot; 0 collapses it flush to the card.
    private var trailingWidth: CGFloat {
        if event.isRunning { return 96 }                 // timer, or Stop when revealed
        if event.canStart && isRevealed { return 96 }    // Start pill
        return 0
    }

    var body: some View {
        HStack(spacing: trailingWidth > 0 ? 8 : 0) {
            EventRowView(event: event)
                .contentShape(Rectangle())
                .onTapGesture { onToggle() }

            trailing
                .frame(width: trailingWidth)
                .clipped()
        }
        .animation(.easeInOut(duration: 0.28), value: isRevealed)
        .animation(.easeInOut(duration: 0.28), value: event.isRunning)
        // Live auto-complete while the app is foreground and this row is on
        // screen: wait out the remaining time, then flip to complete. Restarts
        // if the event is (re)started. Off-screen/backgrounded finishes are
        // handled by TodayView's scenePhase reconciliation instead.
        .task(id: event.startedAt) {
            guard event.isRunning, let finish = event.finishTime else { return }
            let delay = finish.timeIntervalSinceNow
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            if !Task.isCancelled, event.isRunning { onFinish() }
        }
    }

    // Which single state the trailing slot is showing. All three views are kept
    // mounted (below) and crossfaded by opacity — no identity insert/remove and
    // no `move`, so nothing tears.
    private var showTimer: Bool { event.isRunning && !isRevealed }
    private var showStop:  Bool { event.isRunning && isRevealed }
    private var showStart: Bool { !event.isRunning && event.canStart && isRevealed }

    /// All three trailing states stacked and crossfaded purely by opacity. The
    /// timer uses a stable fallback range (the event's own start/end when not
    /// started) so it's always mountable and never inserts/removes. Hidden views
    /// also drop hit-testing so an invisible pill can't capture a tap.
    private var trailing: some View {
        ZStack {
            runningTimer(from: event.startedAt ?? event.startTime,
                         to: event.finishTime ?? event.endTime)
                .opacity(showTimer ? 1 : 0)
                .allowsHitTesting(showTimer)

            pill("Stop", icon: "stop.fill", fill: AnyShapeStyle(Color.red.gradient), action: onStop)
                .opacity(showStop ? 1 : 0)
                .allowsHitTesting(showStop)

            pill("Start", icon: "play.fill", fill: AnyShapeStyle(theme.pillGradient), action: onStart)
                .opacity(showStart ? 1 : 0)
                .allowsHitTesting(showStart)
        }
    }

    /// A full-card-height action pill (radius matches `cardStyle`, 18). Icon over
    /// text so the glyph reads large and the content fills the tall, narrow pill.
    private func pill(_ title: String, icon: String, fill: AnyShapeStyle, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                Text(title)
                    .font(.caption2.weight(.bold))
                    .lineLimit(1)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Self-updating MM:SS countdown — `Text(timerInterval:)` ticks on its own
    /// with no timer or state, exactly the render-driven model we want.
    private func runningTimer(from start: Date, to finish: Date) -> some View {
        Text(timerInterval: start...finish, countsDown: true)
            .font(.cadBodyStrong.monospacedDigit())
            .foregroundColor(theme.accent)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.chipBg)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            // Tapping the timer (not just the card) reveals the Stop pill.
            // `onToggle` only flips the reveal state, so this can't start a
            // second run or stack a Live Activity.
            .contentShape(Rectangle())
            .onTapGesture { onToggle() }
    }
}
