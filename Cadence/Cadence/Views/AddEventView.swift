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

    var body: some View {
        NavigationStack {
            ZStack {
                theme.backgroundGradient.ignoresSafeArea()
                Form {
                    Section("Details") {
                        TextField("Event title", text: $title)
                        DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                            .tint(theme.accent)
                        DatePicker("Starts", selection: $startTime, displayedComponents: .hourAndMinute)
                            .tint(theme.accent)
                        DatePicker("Ends", selection: $endTime, displayedComponents: .hourAndMinute)
                            .tint(theme.accent)
                        if !isTimeRangeValid {
                            Label("End time must be after start time.", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundColor(.red)
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
                    selectedDate = ev.startTime
                    startTime = ev.startTime
                    endTime = ev.endTime
                    selectedCategory = ev.category
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

        try? context.save()
        WidgetSync.refresh()
        dismiss()
    }
}
