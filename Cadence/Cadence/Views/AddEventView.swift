import SwiftUI
import SwiftData

struct AddEventView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var categories: [Category]
    @Query(sort: \Event.startTime) private var allEvents: [Event]
    @Query private var prefsResults: [UserPreferences]

    var prefillTitle: String = ""
    var editingEvent: Event? = nil

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
                Color.cadenceCream.ignoresSafeArea()
                Form {
                    Section("Details") {
                        TextField("Event title", text: $title)
                        DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                            .tint(.cadenceOrange)
                        DatePicker("Starts", selection: $startTime, displayedComponents: .hourAndMinute)
                            .tint(.cadenceOrange)
                        DatePicker("Ends", selection: $endTime, displayedComponents: .hourAndMinute)
                            .tint(.cadenceOrange)
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
                                            .foregroundColor(.cadenceOrange)
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
                        .foregroundColor(.cadenceOrange)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { attemptSave() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                        .foregroundColor(title.trimmingCharacters(in: .whitespaces).isEmpty ? .secondary : .cadenceOrange)
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
                } else if !prefillTitle.isEmpty {
                    title = prefillTitle
                }
            }
        }
    }

    // MARK: - Helpers

    private var combinedStart: Date { combine(time: startTime, with: selectedDate) }
    private var combinedEnd: Date   { combine(time: endTime,   with: selectedDate) }

    private func combine(time: Date, with date: Date) -> Date {
        let cal   = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: time)
        return cal.date(bySettingHour: comps.hour ?? 0, minute: comps.minute ?? 0, second: 0, of: date) ?? time
    }

    private func attemptSave() {
        let prefs    = prefsResults.first ?? UserPreferences()
        let proposal = DateInterval(start: combinedStart, end: combinedEnd)
        // Exclude the event being edited from conflict check
        let others   = editingEvent.map { ev in allEvents.filter { $0.id != ev.id } } ?? allEvents
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
            svc.scheduleMissedEventAlert(for: event)
        }
        try? context.save()
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
                svc.scheduleMissedEventAlert(for: event)
            }
        } else {
            event.startTime = combinedStart
            event.endTime = combinedEnd
        }

        try? context.save()
        dismiss()
    }
}
