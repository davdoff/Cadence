import SwiftUI
import SwiftData

struct AddEventView: View {
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var categories: [Category]
    @Query(sort: \Event.startTime) private var allEvents: [Event]
    @Query private var prefsResults: [UserPreferences]

    var prefillTitle: String = ""
    var editingEvent: Event? = nil
    /// Pre-selects this day for new events (e.g. the day picked in ScheduleView).
    var initialDate: Date? = nil
    /// Missed-tray reschedule: prefills title/category/times from this event
    /// and deletes it only when the replacement is saved — cancelling the
    /// sheet keeps the original (UI_REVIEW §1.2).
    var reschedulingSource: Event? = nil

    @State private var title = ""
    @State private var selectedDate = Date.now
    @State private var startTime: Date = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now
    @State private var endTime: Date   = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: .now) ?? .now
    @State private var selectedCategory: Category?
    @State private var showConflictAlert = false
    @State private var conflictNames = ""
    @State private var repeatChoice: RepeatChoice = .never
    @State private var repeatInterval = 1
    @State private var repeatHasEndDate = false
    @State private var repeatEndDate: Date = Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now

    // Bulk-edit scope (edit mode only). Populated in onAppear.
    /// True when editing an occurrence of a *native* recurring series — enables
    /// the "change all occurrences" scope toggle.
    @State private var isNativeSeries = false
    @State private var applyToAllOccurrences = false
    @State private var seriesEditScope: SeriesEditScope = .thisAndFuture
    /// Non-recurring events that share this event's title, so we can offer a
    /// "set category on all named X" toggle. Title captured at open time.
    @State private var siblingCount = 0
    @State private var originalTitle = ""
    @State private var applyCategoryToSiblings = false

    /// "Never" + the four RecurrenceRule frequencies, for the Repeats picker.
    private enum RepeatChoice: String, CaseIterable, Identifiable {
        case never, daily, weekly, monthly, yearly

        var id: String { rawValue }

        var label: String {
            switch self {
            case .never:   return "Never"
            case .daily:   return "Daily"
            case .weekly:  return "Weekly"
            case .monthly: return "Monthly"
            case .yearly:  return "Yearly"
            }
        }

        var unitName: String {
            switch self {
            case .never:   return ""
            case .daily:   return "day"
            case .weekly:  return "week"
            case .monthly: return "month"
            case .yearly:  return "year"
            }
        }

        var frequency: RecurrenceRule.Frequency? {
            switch self {
            case .never:   return nil
            case .daily:   return .daily
            case .weekly:  return .weekly
            case .monthly: return .monthly
            case .yearly:  return .yearly
            }
        }

        init(frequency: RecurrenceRule.Frequency) {
            switch frequency {
            case .daily:   self = .daily
            case .weekly:  self = .weekly
            case .monthly: self = .monthly
            case .yearly:  self = .yearly
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                theme.backgroundGradient.ignoresSafeArea()
                Form {
                    Section("Details") {
                        TextField("Event title", text: $title)
                        DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                            .tint(theme.accent)
                    }

                    Section("Time") {
                        ClockTimePicker(start: $startTime, end: $endTime)
                        if !isTimeRangeValid {
                            Label("End time must be after start time.", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }

                    // Imported events mirror their source calendar's rule,
                    // so recurrence isn't editable from here.
                    if editingEvent?.source != .imported {
                        Section("Repeats") {
                            Picker("Repeats", selection: $repeatChoice) {
                                ForEach(RepeatChoice.allCases) { choice in
                                    Text(choice.label).tag(choice)
                                }
                            }
                            .tint(theme.accent)
                            if repeatChoice != .never {
                                Stepper(value: $repeatInterval, in: 1...99) {
                                    Text(repeatIntervalLabel)
                                }
                                Toggle("End date", isOn: $repeatHasEndDate)
                                    .tint(theme.accent)
                                if repeatHasEndDate {
                                    DatePicker("Ends", selection: $repeatEndDate, displayedComponents: .date)
                                        .tint(theme.accent)
                                }
                            }
                        }
                    }

                    Section("Category") {
                        ForEach(categories) { cat in
                            Button {
                                selectedCategory = (selectedCategory?.id == cat.id) ? nil : cat
                            } label: {
                                HStack {
                                    Circle()
                                        .fill(Color(hex: cat.colorHex))
                                        .frame(width: 12, height: 12)
                                    Text(cat.name)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if selectedCategory?.id == cat.id {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(theme.accent)
                                    }
                                }
                            }
                        }
                    }

                    if editingEvent != nil {
                        applyScopeSection
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(editingEvent == nil ? "Add Event" : "Edit Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(theme.accent)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { attemptSave() }
                        .disabled(!canSave)
                        .foregroundColor(canSave ? theme.accent : .secondary)
                }
            }
            .alert("Scheduling Conflict", isPresented: $showConflictAlert) {
                Button("Save Anyway") { editingEvent == nil ? forceInsert() : forceUpdate() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This overlaps with: \(conflictNames). Save anyway?")
            }
            .onAppear {
                if let ev = editingEvent {
                    title = ev.title
                    originalTitle = ev.title
                    selectedDate = ev.startTime
                    startTime = ev.startTime
                    endTime = ev.endTime
                    selectedCategory = ev.category
                    if let series = RecurrenceService.shared.series(for: ev, context: context) {
                        isNativeSeries = true
                        repeatChoice = RepeatChoice(frequency: series.frequency)
                        repeatInterval = series.interval
                        if let end = series.endDate {
                            repeatHasEndDate = true
                            repeatEndDate = end
                        }
                    } else if ev.seriesID == nil {
                        // One-off event: offer bulk category only if it has same-title siblings.
                        siblingCount = EventBulkService.siblingCount(of: ev, context: context)
                    }
                } else if let src = reschedulingSource {
                    title = src.title
                    selectedCategory = src.category
                    startTime = src.startTime
                    endTime = src.endTime
                } else {
                    if !prefillTitle.isEmpty { title = prefillTitle }
                    if let initialDate { selectedDate = initialDate }
                }
            }
        }
    }

    // MARK: - Bulk-edit scope UI

    /// Edit-mode section letting the user push this edit beyond the single
    /// occurrence. For a native series: a "change all occurrences" toggle that
    /// reveals a scope picker only once ticked (keeps the sheet uncluttered).
    /// For a one-off event with same-title siblings: a "set category on all
    /// named X" toggle.
    @ViewBuilder
    private var applyScopeSection: some View {
        if isNativeSeries {
            Section("Apply to") {
                Toggle("Change all occurrences", isOn: $applyToAllOccurrences)
                    .tint(theme.accent)
                if applyToAllOccurrences {
                    Picker("Occurrences", selection: $seriesEditScope) {
                        Text("This & future").tag(SeriesEditScope.thisAndFuture)
                        Text("All (incl. past)").tag(SeriesEditScope.all)
                    }
                    .tint(theme.accent)
                }
            }
        } else if siblingCount > 0 {
            Section("Apply to") {
                Toggle("Set category on all \(siblingCount + 1) events named “\(originalTitle)”",
                       isOn: $applyCategoryToSiblings)
                    .tint(theme.accent)
            }
        }
    }

    // MARK: - Helpers

    private var combinedStart: Date { combine(time: startTime, with: selectedDate) }
    private var combinedEnd: Date   { combine(time: endTime,   with: selectedDate) }

    /// DateInterval traps on a negative duration — never build one from an
    /// inverted range (UI_REVIEW §1.1).
    private var isTimeRangeValid: Bool { combinedEnd > combinedStart }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && isTimeRangeValid
    }

    private func combine(time: Date, with date: Date) -> Date {
        let cal   = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: time)
        return cal.date(bySettingHour: comps.hour ?? 0, minute: comps.minute ?? 0, second: 0, of: date) ?? time
    }

    // MARK: - Recurrence

    private var repeatIntervalLabel: String {
        let unit = repeatChoice.unitName
        return repeatInterval == 1 ? "Every \(unit)" : "Every \(repeatInterval) \(unit)s"
    }

    /// The rule the form currently describes; nil when "Never". The end date
    /// is pushed to end-of-day so an occurrence ON the chosen day still fits.
    private var composedRule: RecurrenceRule? {
        guard let frequency = repeatChoice.frequency else { return nil }
        let end = repeatHasEndDate
            ? Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: repeatEndDate)
            : nil
        return RecurrenceRule(frequency: frequency, interval: repeatInterval, endDate: end)
    }

    /// Editing only: reconciles the form's rule with the event's series.
    /// Time/title edits stay occurrence-only; rule changes are series-wide
    /// (this and future occurrences).
    private func applyRecurrenceChange(to event: Event) {
        guard event.source != .imported else { return }
        let series = RecurrenceService.shared.series(for: event, context: context)
        switch (series, composedRule) {
        case (nil, let rule?):
            RecurrenceService.shared.createSeries(from: event, rule: rule, context: context)
        case (.some, nil):
            RecurrenceService.shared.endSeries(from: event, context: context)
        case (let series?, let rule?) where series.rule != rule:
            RecurrenceService.shared.updateRule(from: event, to: rule, context: context)
        default:
            break
        }
    }

    private func attemptSave() {
        guard isTimeRangeValid else { return }
        let prefs    = prefsResults.first ?? UserPreferences()
        let proposal = DateInterval(start: combinedStart, end: combinedEnd)
        // Exclude the event being edited/replaced from the conflict check
        let excludedID = editingEvent?.id ?? reschedulingSource?.id
        let others   = excludedID.map { id in allEvents.filter { $0.id != id } } ?? allEvents
        let hits     = SchedulerService().conflicts(for: proposal, in: others, bufferMinutes: prefs.bufferMinutes)

        if hits.isEmpty {
            editingEvent == nil ? forceInsert() : forceUpdate()
        } else {
            conflictNames = hits.map(\.title).joined(separator: ", ")
            showConflictAlert = true
        }
    }

    private func forceInsert() {
        let event = Event(
            title: title.trimmingCharacters(in: .whitespaces),
            startTime: combinedStart,
            endTime: combinedEnd,
            category: selectedCategory
        )
        context.insert(event)
        let prefs = prefsResults.first ?? UserPreferences()
        let svc = NotificationService()
        if svc.isNotificationEnabled(for: event, prefs: prefs) {
            event.notificationIdentifier = svc.scheduleEventReminder(
                for: event, reminderMinutes: prefs.defaultReminderMinutes
            )
            svc.scheduleEventStartAlert(for: event, reminderMinutes: prefs.defaultReminderMinutes)
            svc.scheduleMissedEventAlert(for: event)
        }
        if let rule = composedRule {
            RecurrenceService.shared.createSeries(from: event, rule: rule, context: context)
        }
        // The replacement is saved — now it's safe to drop the missed original.
        if let src = reschedulingSource {
            svc.cancelEventNotifications(for: src)
            // Imported events: tombstone so the next sync doesn't re-insert it.
            CalendarImportService.shared.noteLocalDeletion(of: src, context: context)
            context.delete(src)
        }
        try? context.save()
        WidgetSync.refresh()
        dismiss()
    }

    private func forceUpdate() {
        guard let event = editingEvent else { return }
        let prefs = prefsResults.first ?? UserPreferences()
        let svc = NotificationService()

        let timeChanged = event.startTime != combinedStart || event.endTime != combinedEnd

        event.title = title.trimmingCharacters(in: .whitespaces)
        event.category = selectedCategory

        if timeChanged {
            svc.cancelEventNotifications(for: event)
            event.startTime = combinedStart
            event.endTime = combinedEnd
            event.status = .pending
            if svc.isNotificationEnabled(for: event, prefs: prefs) {
                event.notificationIdentifier = svc.scheduleEventReminder(
                    for: event, reminderMinutes: prefs.defaultReminderMinutes
                )
                svc.scheduleEventStartAlert(for: event, reminderMinutes: prefs.defaultReminderMinutes)
                svc.scheduleMissedEventAlert(for: event)
            }
        } else {
            event.startTime = combinedStart
            event.endTime = combinedEnd
        }

        applyRecurrenceChange(to: event)

        // Propagate the edit beyond this occurrence when the user opted in.
        if applyToAllOccurrences, isNativeSeries {
            RecurrenceService.shared.applyOccurrenceEdit(
                from: event,
                scope: seriesEditScope,
                title: event.title,
                category: event.category,
                startTimeOfDay: Calendar.current.dateComponents([.hour, .minute], from: startTime),
                duration: combinedEnd.timeIntervalSince(combinedStart),
                context: context
            )
        } else if applyCategoryToSiblings {
            // Match on the title the siblings were grouped by, not a rename.
            EventBulkService.setCategory(event.category, forEventsTitled: originalTitle, context: context)
        }

        try? context.save()
        WidgetSync.refresh()
        dismiss()
    }
}
