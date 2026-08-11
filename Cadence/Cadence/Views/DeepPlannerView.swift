import SwiftUI
import SwiftData

/// The Deep Planner surface — the primary half of the Overview tab (see
/// `OverviewTabView`). Turns a long-term goal into a thin whole-horizon
/// skeleton, then plans one week of focused sessions at a time, advancing on
/// completion + feedback. See `deep-planner-plan.md` for the full loop.
///
/// Increment 1: intake → skeleton + cushion. Weekly planning, the review card,
/// and multiturn intake arrive next (deep-planner-plan.md §7).
struct DeepPlannerView: View {
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var context
    @Query(sort: \ProjectPlan.createdAt, order: .reverse) private var plans: [ProjectPlan]
    @Query(sort: \Event.startTime) private var allEvents: [Event]
    @Query private var prefsResults: [UserPreferences]
    @Query private var categories: [Category]

    @AppStorage("activePlanID") private var activePlanIDString = ""

    @State private var showIntake = false
    @State private var isPlanning = false
    @State private var isFindingNext = false
    @State private var planError: String?
    @State private var lastPlannedCount: Int?
    @State private var sessionDraft: PlanSessionDraft?

    // Session editing / gallery-style multi-select for AI tweaks.
    @State private var isSelecting = false
    @State private var selectedSessionIDs: Set<UUID> = []
    @State private var editingEvent: Event?
    @State private var tweakRequest: TweakRequest?

    /// Wrapper so the tweak sheet is presented `item`-style with a snapshot of the
    /// chosen sessions (selection state can change underneath it otherwise).
    private struct TweakRequest: Identifiable {
        let id = UUID()
        let plan: ProjectPlan
        let events: [Event]
    }

    /// The selected plan, or the newest when the stored id is missing (fresh
    /// install, or right after deleting the active plan).
    private var activePlan: ProjectPlan? {
        plans.first { $0.id.uuidString == activePlanIDString } ?? plans.first
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let plan = activePlan {
                    planView(plan)
                } else {
                    emptyState
                }
            }
            .padding()
            .padding(.bottom, 20)
        }
        .toolbar {
            if activePlan != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showIntake = true } label: { Label("New plan", systemImage: "plus") }
                        if let plan = activePlan {
                            Button(role: .destructive) {
                                context.delete(plan)
                                activePlanIDString = ""
                            } label: {
                                Label("Delete plan", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showIntake) {
            DeepPlanIntakeView { newID in
                activePlanIDString = newID.uuidString
            }
        }
        .sheet(item: $sessionDraft) { draft in
            PlanSessionSchedulerView(draft: draft)
        }
        .sheet(item: $editingEvent) { event in
            AddEventView(editingEvent: event)
        }
        .sheet(item: $tweakRequest) { req in
            PlanTweakSheet(plan: req.plan, sessions: req.events)
        }
    }

    // MARK: - Active plan

    @ViewBuilder
    private func planView(_ plan: ProjectPlan) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                planTitleHeader(plan)
                HStack(spacing: 6) {
                    Text(plan.goalType == .study ? "Study" : "Project")
                    if let deadline = plan.deadline {
                        Text("·").foregroundColor(theme.text2)
                        Text("by \(deadline.formatted(.dateTime.month().day()))")
                    }
                }
                .font(.subheadline)
                .foregroundColor(theme.text2)
            }

            cushionBadge(plan)
            planWeekButton(plan)
            scheduleNextButton(plan)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(plan.orderedUnits) { unitRow($0) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .cardStyle()

        let sessions = planSessions(for: plan)
        if !sessions.isEmpty {
            sessionsSection(plan, sessions)
        }
    }

    // MARK: - Scheduled sessions (edit manually, or tweak with AI)

    /// This plan's scheduled sessions from today onward, soonest first. Past
    /// sessions are hidden to keep the list about what's still actionable.
    private func planSessions(for plan: ProjectPlan) -> [Event] {
        let dayStart = Calendar.current.startOfDay(for: .now)
        return allEvents
            .filter { $0.planID == plan.id && $0.endTime >= dayStart }
            .sorted { $0.startTime < $1.startTime }
    }

    private var selectedEvents: [Event] {
        guard let plan = activePlan else { return [] }
        return planSessions(for: plan).filter { selectedSessionIDs.contains($0.id) }
    }

    @ViewBuilder
    private func sessionsSection(_ plan: ProjectPlan, _ sessions: [Event]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Sessions")
                    .font(.headline).foregroundColor(theme.text)
                Spacer()
                Button(isSelecting ? "Done" : "Select") {
                    withAnimation { isSelecting.toggle() }
                    if !isSelecting { selectedSessionIDs.removeAll() }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(theme.accent)
            }

            VStack(spacing: 8) {
                ForEach(sessions) { sessionRow($0) }
            }

            if isSelecting {
                Button { startTweak(plan) } label: {
                    Label(selectedSessionIDs.isEmpty ? "Tweak with AI"
                                                      : "Tweak \(selectedSessionIDs.count) with AI",
                          systemImage: "wand.and.stars")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(theme.accentGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(selectedSessionIDs.isEmpty)
                .opacity(selectedSessionIDs.isEmpty ? 0.5 : 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .cardStyle()
    }

    @ViewBuilder
    private func sessionRow(_ event: Event) -> some View {
        let selected = selectedSessionIDs.contains(event.id)
        Button {
            if isSelecting { toggleSelection(event) } else { editingEvent = event }
        } label: {
            HStack(spacing: 10) {
                if isSelecting {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(selected ? theme.accent : theme.text2)
                        .font(.title3)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(event.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(theme.text)
                            .strikethrough(event.status == .completed)
                        if event.status == .completed {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption).foregroundColor(.green)
                        }
                    }
                    Text(sessionTimeLabel(event))
                        .font(.caption).foregroundColor(theme.text2)
                    if let objective = event.objective, !objective.isEmpty {
                        Text(objective)
                            .font(.caption).foregroundColor(theme.text2).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                if !isSelecting {
                    Image(systemName: "chevron.right").font(.caption).foregroundColor(theme.light)
                }
            }
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { editingEvent = event } label: { Label("Edit time & title", systemImage: "pencil") }
            Button { markDone(event) } label: { Label("Mark done", systemImage: "checkmark.circle") }
            if let plan = activePlan {
                Button { tweakRequest = TweakRequest(plan: plan, events: [event]) } label: {
                    Label("Tweak with AI", systemImage: "wand.and.stars")
                }
            }
        }
    }

    private func toggleSelection(_ event: Event) {
        if selectedSessionIDs.contains(event.id) { selectedSessionIDs.remove(event.id) }
        else { selectedSessionIDs.insert(event.id) }
    }

    private func startTweak(_ plan: ProjectPlan) {
        let events = selectedEvents
        guard !events.isEmpty else { return }
        tweakRequest = TweakRequest(plan: plan, events: events)
        withAnimation { isSelecting = false }
        selectedSessionIDs.removeAll()
    }

    private func markDone(_ event: Event) {
        event.status = .completed
        NotificationService().cancelEventNotifications(for: event)
        try? context.save()
        WidgetSync.refresh()
    }

    private func sessionTimeLabel(_ event: Event) -> String {
        let day = event.startTime.formatted(.dateTime.weekday(.abbreviated).month().day())
        let start = event.startTime.formatted(.dateTime.hour().minute())
        let end = event.endTime.formatted(.dateTime.hour().minute())
        return "\(day) · \(start)–\(end)"
    }

    /// Plan title as a switcher: tap to pick among stored plans. The chevron
    /// only appears when there's more than one plan to switch to.
    @ViewBuilder
    private func planTitleHeader(_ plan: ProjectPlan) -> some View {
        Menu {
            ForEach(plans) { p in
                Button {
                    activePlanIDString = p.id.uuidString
                } label: {
                    if p.id == plan.id {
                        Label(p.title, systemImage: "checkmark")
                    } else {
                        Text(p.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(plan.title)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(theme.text)
                    .multilineTextAlignment(.leading)
                if plans.count > 1 {
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(theme.text2)
                }
            }
        }
        .disabled(plans.count <= 1)
    }

    private func planWeekButton(_ plan: ProjectPlan) -> some View {
        VStack(spacing: 6) {
            Button { planThisWeek(plan) } label: {
                Group {
                    if isPlanning {
                        ProgressView().tint(.white)
                    } else {
                        Label("Plan this week", systemImage: "calendar.badge.plus")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(theme.accentGradient)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(isPlanning)

            if let planError {
                Text(planError).font(.caption).foregroundColor(.red)
            } else if let n = lastPlannedCount {
                Text(n == 0 ? "Nothing new to schedule this week — you're on track."
                            : "Added \(n) session\(n == 1 ? "" : "s") to your week.")
                    .font(.caption).foregroundColor(theme.text2)
            }
        }
    }

    /// Secondary path: place one session at a time, by hand. Asks the server for
    /// the sessions due this week (same deterministic call), takes the first, and
    /// opens the editor preset to its soonest opening — the user picks where it lands.
    private func scheduleNextButton(_ plan: ProjectPlan) -> some View {
        Button { scheduleNextSession(plan) } label: {
            Group {
                if isFindingNext {
                    ProgressView().tint(theme.accent)
                } else {
                    Label("Schedule a session myself", systemImage: "hand.point.up.left")
                        .font(.subheadline.weight(.semibold))
                }
            }
            .foregroundColor(theme.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.accent.opacity(0.5), lineWidth: 1))
        }
        .disabled(isFindingNext || isPlanning)
    }

    // MARK: - Weekly placement

    /// The `/v1/plan/week` inputs, snapshotted on the main actor (SwiftData reads
    /// must not cross to the Task). Shared by the auto and manual paths.
    private struct WeekInputs {
        let planID: UUID
        let goalType: String
        let deadline: Date?
        let weeklyHours: Int
        let units: [WorkUnitData]
        let progress: [WorkUnitProgress]
        let windowStart: Date
        let windowEnd: Date
        let prefs: UserPreferences
        let events: [Event]
    }

    private func weekInputs(_ plan: ProjectPlan) -> WeekInputs {
        let windowStart = Date.now
        return WeekInputs(
            planID: plan.id,
            goalType: plan.goalType == .project ? "project" : "study",
            deadline: plan.deadline,
            weeklyHours: plan.weeklyHours,
            units: plan.orderedUnits.map { u in
                WorkUnitData(
                    id: u.unitKey, title: u.title, objective: u.objective,
                    estimatedMinutes: u.estimatedMinutes,
                    archetype: u.archetype == .repetition ? "repetition" : "milestone",
                    afterUnit: u.afterUnit, repeatOf: u.repeatOf,
                    minGapDays: u.minGapDays, notLastNDaysBeforeDeadline: u.notLastNDaysBeforeDeadline
                )
            },
            progress: progressFor(plan),
            windowStart: windowStart,
            windowEnd: Calendar.current.date(byAdding: .day, value: 7, to: windowStart) ?? windowStart,
            prefs: prefsResults.first ?? UserPreferences(),
            events: allEvents
        )
    }

    private func requestSessions(_ i: WeekInputs) async throws -> [PlannedEventData] {
        try await AIService().planWeek(
            goalType: i.goalType, deadline: i.deadline, workUnits: i.units,
            windowStart: i.windowStart, windowEnd: i.windowEnd, weeklyHours: i.weeklyHours,
            progress: i.progress, events: i.events,
            preferences: i.prefs, categories: categories
        )
    }

    /// Deterministic weekly placement: ask the server which sessions are due, then
    /// insert them all as linked Events at the soonest slots (never in the past —
    /// the server clamps the window to `now`).
    private func planThisWeek(_ plan: ProjectPlan) {
        guard !isPlanning else { return }
        planError = nil
        lastPlannedCount = nil
        isPlanning = true
        let inputs = weekInputs(plan)

        Task {
            do {
                let planned = try await requestSessions(inputs)
                insertSessions(planned, planID: inputs.planID, prefs: inputs.prefs)
                lastPlannedCount = planned.count
            } catch {
                planError = (error as? AIServiceError)?.errorDescription ?? "Couldn't plan the week. Try again."
            }
            isPlanning = false
        }
    }

    /// Take the next due session and hand it to the manual editor. Building the
    /// draft (not inserting) is the whole difference from `planThisWeek`.
    private func scheduleNextSession(_ plan: ProjectPlan) {
        guard !isFindingNext else { return }
        planError = nil
        lastPlannedCount = nil
        isFindingNext = true
        let inputs = weekInputs(plan)

        Task {
            do {
                let planned = try await requestSessions(inputs)
                if let next = planned.first {
                    let minutes = max(15, Int(next.end.timeIntervalSince(next.start) / 60))
                    sessionDraft = PlanSessionDraft(
                        planID: inputs.planID, workUnitID: next.workUnitId,
                        title: next.title, objective: next.objective,
                        categoryName: next.categoryName, durationMinutes: minutes
                    )
                } else {
                    lastPlannedCount = 0
                }
            } catch {
                planError = (error as? AIServiceError)?.errorDescription ?? "Couldn't find the next session. Try again."
            }
            isFindingNext = false
        }
    }

    /// Per-unit progress from events already linked to this plan — so scheduled
    /// work isn't replanned and recall gaps are measured from the last session.
    private func progressFor(_ plan: ProjectPlan) -> [WorkUnitProgress] {
        let linked = allEvents.filter { $0.planID == plan.id }
        return plan.orderedUnits.map { unit in
            let unitEvents = linked.filter { $0.workUnitID == unit.unitKey }
            let scheduled = unitEvents.reduce(0) { $0 + Int($1.duration / 60) }
            return WorkUnitProgress(
                workUnitId: unit.unitKey,
                scheduledMinutes: scheduled,
                lastSessionDate: unitEvents.map(\.startTime).max()
            )
        }
    }

    private func insertSessions(_ sessions: [PlannedEventData], planID: UUID, prefs: UserPreferences) {
        let svc = NotificationService()
        for session in sessions {
            let event = Event(
                title: session.title,
                startTime: session.start,
                endTime: session.end,
                category: resolveOrCreateCategory(named: session.categoryName),
                source: .ai
            )
            event.planID = planID
            event.workUnitID = session.workUnitId
            event.objective = session.objective
            context.insert(event)
            scheduleNotifications(for: event, prefs: prefs, svc: svc)
        }
        try? context.save()
        WidgetSync.refresh()
    }

    /// Existing category by case-insensitive name, or a new one (mirrors the
    /// AIInputView rule — never fail a plan just because a category is new).
    private func resolveOrCreateCategory(named name: String) -> Category? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if let existing = categories.first(where: { $0.name.lowercased() == trimmed.lowercased() }) {
            return existing
        }
        let palette = AddCategoryView.palette
        let created = Category(name: trimmed, colorHex: palette[abs(trimmed.hashValue) % palette.count])
        context.insert(created)
        return created
    }

    private func scheduleNotifications(for event: Event, prefs: UserPreferences, svc: NotificationService) {
        guard svc.isNotificationEnabled(for: event, prefs: prefs) else { return }
        event.notificationIdentifier = svc.scheduleEventReminder(
            for: event, reminderMinutes: prefs.defaultReminderMinutes
        )
        svc.scheduleEventStartAlert(for: event, reminderMinutes: prefs.defaultReminderMinutes)
        svc.scheduleMissedEventAlert(for: event)
    }

    private func cushionBadge(_ plan: ProjectPlan) -> some View {
        let cushion = plan.cushionMinutes
        let over = cushion < 0
        return HStack(spacing: 8) {
            Image(systemName: over ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
            Text(over
                 ? "Over by \(hoursLabel(-cushion)) — cut scope or add time"
                 : "\(hoursLabel(cushion)) cushion")
                .font(.subheadline.weight(.medium))
        }
        .foregroundColor(over ? .red : .green)
        .padding(.vertical, 8).padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func unitRow(_ unit: WorkUnit) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(unit.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(theme.text)
                Spacer()
                Text(hoursLabel(unit.estimatedMinutes))
                    .font(.caption).foregroundColor(theme.text2)
            }
            Text(unit.objective)
                .font(.caption)
                .foregroundColor(theme.text2)
            HStack(spacing: 6) {
                tag(unit.archetype == .repetition ? "recall" : "milestone")
                if unit.repeatOf != nil { tag("revisit") }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Divider().opacity(unit.order == 0 ? 0 : 1) }
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundColor(theme.accent)
            .padding(.vertical, 2).padding(.horizontal, 7)
            .background(theme.accent.opacity(0.12))
            .clipShape(Capsule())
    }

    /// Minutes → "3h 30m" / "45m" / "2h".
    private func hoursLabel(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    // MARK: - Empty state (no active plan)

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "target")
                .font(.system(size: 52))
                .foregroundColor(theme.light)

            Text("Plan a goal")
                .font(.title3.weight(.semibold))
                .foregroundColor(theme.text)

            Text("Give the planner a goal — an exam, a project, a skill — and it plans one focused week at a time, adapting as you go.")
                .font(.subheadline)
                .foregroundColor(theme.text2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button {
                showIntake = true
            } label: {
                Text("Start a plan")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(theme.accentGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 24)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}
