import SwiftUI
import SwiftData

/// The next work-unit session, ready to place. `DeepPlannerView` builds this from
/// the deterministic `/v1/plan/week` result (which unit is due + how long a chunk),
/// then hands it to `PlanSessionSchedulerView`, which owns *where* it lands.
struct PlanSessionDraft: Identifiable {
    let id = UUID()
    let planID: UUID
    let workUnitID: String
    let title: String
    let objective: String
    let categoryName: String       // "Study" / "Work" from the plan's goal type
    let durationMinutes: Int       // the session chunk the planner would place
}

/// Manual, one-at-a-time session placement for the deep planner — the opposite of
/// the "Plan this week" magic button. Opens preset to the soonest free opening but
/// fully adjustable: chips for the next openings, time-of-day jumps, and duration,
/// plus manual date/time. Saving inserts one `Event` linked back to the plan
/// (`planID` / `workUnitID` / `objective`) — the same link the auto path uses.
struct PlanSessionSchedulerView: View {
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Event.startTime) private var allEvents: [Event]
    @Query private var prefsResults: [UserPreferences]
    @Query private var categories: [Category]

    let draft: PlanSessionDraft

    @State private var selectedDate = Date.now
    @State private var startTime = Date.now
    @State private var endTime = Date.now
    @State private var selectedCategory: Category?
    @State private var didInit = false
    @State private var showConflictAlert = false
    @State private var conflictNames = ""

    private let durationChips = [30, 60, 90, 120]

    var body: some View {
        NavigationStack {
            ZStack {
                theme.backgroundGradient.ignoresSafeArea()
                Form {
                    objectiveSection
                    openingsSection
                    timeOfDaySection
                    lengthSection
                    Section("When") {
                        DatePicker("Date", selection: $selectedDate, in: dayFloor..., displayedComponents: .date)
                            .tint(theme.accent)
                        ClockTimePicker(start: $startTime, end: $endTime)
                        if !isTimeRangeValid {
                            Label("End time must be after start time.", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption).foregroundColor(.red)
                        } else if combinedStart < Date.now {
                            Label("That time has already passed.", systemImage: "clock.badge.exclamationmark")
                                .font(.caption).foregroundColor(.orange)
                        }
                    }
                    categorySection
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Schedule session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundColor(theme.accent)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { attemptSave() }
                        .disabled(!canSave)
                        .foregroundColor(canSave ? theme.accent : .secondary)
                }
            }
            .alert("Scheduling Conflict", isPresented: $showConflictAlert) {
                Button("Save Anyway") { insert() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This overlaps with: \(conflictNames). Save anyway?")
            }
            .onAppear(perform: primeIfNeeded)
        }
    }

    // MARK: - Sections

    private var objectiveSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(draft.title).font(.headline).foregroundColor(theme.text)
                Text(draft.objective).font(.subheadline).foregroundColor(theme.text2)
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var openingsSection: some View {
        let openings = nextOpenings(count: 4)
        if !openings.isEmpty {
            Section("Soonest openings") {
                chipRow {
                    ForEach(openings, id: \.self) { start in
                        chip(openingLabel(start), selected: sameMinute(combinedStart, start)) {
                            apply(start: start)
                        }
                    }
                }
            }
        }
    }

    private var timeOfDaySection: some View {
        Section("Jump to") {
            chipRow {
                ForEach(TimeOfDayPreset.allCases) { preset in
                    chip(preset.label, selected: false) { apply(start: preset.date(from: prefs)) }
                }
            }
        }
    }

    private var lengthSection: some View {
        Section("Length") {
            chipRow {
                ForEach(durationChips, id: \.self) { minutes in
                    chip(durationLabel(minutes), selected: currentDuration == minutes) {
                        endTime = combinedStart.addingTimeInterval(TimeInterval(minutes * 60))
                    }
                }
            }
        }
    }

    private var categorySection: some View {
        Section("Category") {
            ForEach(categories) { cat in
                Button {
                    selectedCategory = (selectedCategory?.id == cat.id) ? nil : cat
                } label: {
                    HStack {
                        Circle().fill(Color(hex: cat.colorHex)).frame(width: 12, height: 12)
                        Text(cat.name).foregroundColor(.primary)
                        Spacer()
                        if selectedCategory?.id == cat.id {
                            Image(systemName: "checkmark").foregroundColor(theme.accent)
                        }
                    }
                }
            }
            if selectedCategory == nil {
                Text("New “\(draft.categoryName)” category will be created.")
                    .font(.caption).foregroundColor(theme.text2)
            }
        }
    }

    // MARK: - Chip building blocks

    private func chipRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) { content() }.padding(.vertical, 2)
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }

    private func chip(_ text: String, selected: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundColor(selected ? .white : theme.accent)
                .padding(.vertical, 6).padding(.horizontal, 12)
                .background(selected ? AnyShapeStyle(theme.accent) : AnyShapeStyle(theme.accent.opacity(0.12)))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Placement helpers

    private var dayFloor: Date { Calendar.current.startOfDay(for: .now) }
    private var combinedStart: Date { combine(time: startTime, with: selectedDate) }
    private var combinedEnd: Date { combine(time: endTime, with: selectedDate) }
    private var isTimeRangeValid: Bool { combinedEnd > combinedStart }
    private var currentDuration: Int { max(0, Int(combinedEnd.timeIntervalSince(combinedStart) / 60)) }
    private var prefs: UserPreferences { prefsResults.first ?? UserPreferences() }

    private var canSave: Bool { isTimeRangeValid }

    private func combine(time: Date, with date: Date) -> Date {
        let cal = Calendar.current
        let c = cal.dateComponents([.hour, .minute], from: time)
        return cal.date(bySettingHour: c.hour ?? 0, minute: c.minute ?? 0, second: 0, of: date) ?? time
    }

    /// Apply a chosen start, preserving the current session length.
    private func apply(start: Date) {
        let minutes = max(currentDuration, 15)
        selectedDate = start
        startTime = start
        endTime = start.addingTimeInterval(TimeInterval(minutes * 60))
    }

    private func primeIfNeeded() {
        guard !didInit else { return }
        didInit = true
        selectedCategory = categories.first { $0.name.lowercased() == draft.categoryName.lowercased() }
        let start = firstOpening(duration: draft.durationMinutes) ?? nextQuarterHour(after: .now)
        selectedDate = start
        startTime = start
        endTime = start.addingTimeInterval(TimeInterval(draft.durationMinutes * 60))
    }

    /// Free openings that fit `minutes`, clamped so nothing lands in the past
    /// (the client `freeSlots` walks from the start of day and does not clamp).
    private func openings(minutes: Int, count: Int) -> [Date] {
        let now = Date.now
        let end = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        let need = TimeInterval(minutes * 60)
        let slots = SchedulerService().freeSlots(
            duration: minutes, in: now...end, events: allEvents, preferences: prefs
        )
        let starts = slots.compactMap { slot -> Date? in
            let s = nextQuarterHour(after: max(slot.start, now))   // round up, then re-check fit
            return slot.end.timeIntervalSince(s) >= need ? s : nil
        }
        // De-dupe by minute and keep chronological order.
        var seen = Set<Date>(), result: [Date] = []
        for s in starts.sorted() where seen.insert(s).inserted {
            result.append(s)
            if result.count == count { break }
        }
        return result
    }

    private func nextOpenings(count: Int) -> [Date] { openings(minutes: max(currentDuration, 15), count: count) }
    private func firstOpening(duration: Int) -> Date? { openings(minutes: duration, count: 1).first }

    /// Round up to the next :00/:15/:30/:45 so suggested times read cleanly.
    private func nextQuarterHour(after date: Date) -> Date {
        let cal = Calendar.current
        let minute = cal.component(.minute, from: date)
        let add = (15 - minute % 15) % 15
        let bumped = cal.date(byAdding: .minute, value: add == 0 && cal.component(.second, from: date) > 0 ? 15 : add, to: date) ?? date
        return cal.date(bySetting: .second, value: 0, of: bumped) ?? bumped
    }

    private func sameMinute(_ a: Date, _ b: Date) -> Bool {
        abs(a.timeIntervalSince(b)) < 60
    }

    // MARK: - Labels

    private func openingLabel(_ date: Date) -> String {
        let cal = Calendar.current
        let time = date.formatted(.dateTime.hour().minute())
        if cal.isDateInToday(date) { return "Today \(time)" }
        if cal.isDateInTomorrow(date) { return "Tmrw \(time)" }
        return "\(date.formatted(.dateTime.weekday(.abbreviated))) \(time)"
    }

    private func durationLabel(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h\(m)"
    }

    // MARK: - Save

    private func attemptSave() {
        guard isTimeRangeValid else { return }
        let proposal = DateInterval(start: combinedStart, end: combinedEnd)
        let hits = SchedulerService().conflicts(for: proposal, in: allEvents, bufferMinutes: prefs.bufferMinutes)
        if hits.isEmpty {
            insert()
        } else {
            conflictNames = hits.map(\.title).joined(separator: ", ")
            showConflictAlert = true
        }
    }

    private func insert() {
        let event = Event(
            title: draft.title,
            startTime: combinedStart,
            endTime: combinedEnd,
            category: selectedCategory ?? resolveOrCreateCategory(named: draft.categoryName),
            source: .ai
        )
        event.planID = draft.planID
        event.workUnitID = draft.workUnitID
        event.objective = draft.objective
        context.insert(event)

        let svc = NotificationService()
        if svc.isNotificationEnabled(for: event, prefs: prefs) {
            event.notificationIdentifier = svc.scheduleEventReminder(
                for: event, reminderMinutes: prefs.defaultReminderMinutes
            )
            svc.scheduleEventStartAlert(for: event, reminderMinutes: prefs.defaultReminderMinutes)
            svc.scheduleMissedEventAlert(for: event)
        }
        try? context.save()
        WidgetSync.refresh()
        dismiss()
    }

    /// Mirrors DeepPlannerView / AIInputView — never fail placement over a new category.
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
}

/// Rough time-of-day jumps — set a starting point the user then fine-tunes.
private enum TimeOfDayPreset: String, CaseIterable, Identifiable {
    case evening, tomorrowMorning, weekend
    var id: String { rawValue }

    var label: String {
        switch self {
        case .evening:         return "This evening"
        case .tomorrowMorning: return "Tomorrow AM"
        case .weekend:         return "Weekend"
        }
    }

    /// The next matching moment from now, respecting the user's working hours.
    func date(from prefs: UserPreferences) -> Date {
        let cal = Calendar.current
        let now = Date.now
        switch self {
        case .evening:
            let today = cal.date(bySettingHour: 18, minute: 0, second: 0, of: now) ?? now
            return today > now ? today : (cal.date(byAdding: .day, value: 1, to: today) ?? today)
        case .tomorrowMorning:
            let tomorrow = cal.date(byAdding: .day, value: 1, to: now) ?? now
            return cal.date(bySettingHour: prefs.workStartHour, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        case .weekend:
            // Next Saturday (weekday 7 in Cadence's Sun=1 calendar).
            var d = now
            for _ in 0..<7 {
                d = cal.date(byAdding: .day, value: 1, to: d) ?? d
                if cal.component(.weekday, from: d) == 7 { break }
            }
            return cal.date(bySettingHour: prefs.workStartHour, minute: 0, second: 0, of: d) ?? d
        }
    }
}
