import SwiftUI
import SwiftData

/// AI tweak of one or more selected plan sessions — the cheap counterpart to plan
/// generation. Runs the server's default (Sonnet) `/v1/plan/tweak` call, sharing the
/// plan's work units as context, to clarify a vague objective, mark work done, or
/// apply a free-form instruction across the selection. Applies the returned edits to
/// the linked Events (CLAUDE.md rule 3 — the view owns persistence, not AIService).
struct PlanTweakSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var prefsResults: [UserPreferences]

    let plan: ProjectPlan
    let sessions: [Event]

    @State private var instruction = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var results: [String]?   // per-edit summaries once applied

    /// Prefill chips for the two named cases (vague objective, already done) plus a
    /// common one; the text field covers "anything else".
    private let quickIntents: [(label: String, text: String)] = [
        ("I'm not sure what to do", "The objective is too vague — I don't know how to start. Rewrite it into concrete, checkable steps."),
        ("I already did this", "I've already finished this work — mark it done."),
        ("Make it shorter", "This session is too long — shorten it to a more manageable length."),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                theme.backgroundGradient.ignoresSafeArea()
                Form {
                    Section("Selected") {
                        ForEach(sessions) { s in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.title).font(.subheadline.weight(.semibold)).foregroundColor(theme.text)
                                if let o = s.objective, !o.isEmpty {
                                    Text(o).font(.caption).foregroundColor(theme.text2).lineLimit(2)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }

                    if let results {
                        Section("Applied") {
                            if results.isEmpty {
                                Text("The AI didn't change anything.")
                                    .font(.subheadline).foregroundColor(theme.text2)
                            } else {
                                ForEach(Array(results.enumerated()), id: \.offset) { _, line in
                                    Label(line, systemImage: "checkmark.circle.fill")
                                        .font(.subheadline).foregroundColor(theme.text2)
                                }
                            }
                        }
                    } else {
                        Section("Quick tweaks") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(quickIntents, id: \.label) { intent in
                                        chip(intent.label) { instruction = intent.text }
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        }
                        Section("Tell the AI what to change") {
                            TextField("e.g. break the objective into clear steps I can follow",
                                      text: $instruction, axis: .vertical)
                                .lineLimit(2...5)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(sessions.count == 1 ? "Tweak session" : "Tweak \(sessions.count) sessions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(results == nil ? "Cancel" : "Done") { dismiss() }.foregroundColor(theme.accent)
                }
                if results == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(action: apply) {
                            if isWorking { ProgressView() } else { Text("Apply") }
                        }
                        .disabled(!canApply)
                        .foregroundColor(canApply ? theme.accent : .secondary)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption).foregroundColor(.white)
                        .padding(10).frame(maxWidth: .infinity)
                        .background(Color.red.opacity(0.9))
                }
            }
        }
    }

    private func chip(_ text: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundColor(theme.accent)
                .padding(.vertical, 6).padding(.horizontal, 12)
                .background(theme.accent.opacity(0.12))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var canApply: Bool {
        !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isWorking
    }

    private func apply() {
        guard canApply else { return }
        errorMessage = nil
        isWorking = true
        let instr = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let planTitle = plan.title
        let goalType = plan.goalType == .project ? "project" : "study"
        let units = plan.orderedUnits.map { u in
            WorkUnitData(
                id: u.unitKey, title: u.title, objective: u.objective,
                estimatedMinutes: u.estimatedMinutes,
                archetype: u.archetype == .repetition ? "repetition" : "milestone",
                afterUnit: u.afterUnit, repeatOf: u.repeatOf,
                minGapDays: u.minGapDays, notLastNDaysBeforeDeadline: u.notLastNDaysBeforeDeadline
            )
        }
        let inputs = sessions.map {
            AIService.TweakSessionInput(
                ref: $0.id.uuidString, title: $0.title,
                objective: $0.objective ?? "", start: $0.startTime, end: $0.endTime
            )
        }

        Task {
            do {
                let edits = try await AIService().tweakSessions(
                    planTitle: planTitle, goalType: goalType,
                    workUnits: units, sessions: inputs, instruction: instr
                )
                results = applyEdits(edits)
            } catch {
                errorMessage = (error as? AIServiceError)?.errorDescription ?? "Couldn't apply the tweak. Try again."
            }
            isWorking = false
        }
    }

    /// Apply each edit to its matching Event (by id), rescheduling reminders when the
    /// duration changes and clearing them when marked done. Returns display summaries.
    private func applyEdits(_ edits: [SessionEditData]) -> [String] {
        let prefs = prefsResults.first ?? UserPreferences()
        let svc = NotificationService()
        let byID = Dictionary(sessions.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { a, _ in a })
        var summaries: [String] = []

        for edit in edits {
            guard let event = byID[edit.ref] else { continue }
            if let t = edit.title, !t.isEmpty { event.title = t }
            if let o = edit.objective, !o.isEmpty { event.objective = o }

            if let dur = edit.durationMinutes, dur > 0 {
                svc.cancelEventNotifications(for: event)
                event.endTime = event.startTime.addingTimeInterval(TimeInterval(dur * 60))
                if event.status != .completed, svc.isNotificationEnabled(for: event, prefs: prefs) {
                    event.notificationIdentifier = svc.scheduleEventReminder(
                        for: event, reminderMinutes: prefs.defaultReminderMinutes)
                    svc.scheduleEventStartAlert(for: event, reminderMinutes: prefs.defaultReminderMinutes)
                    svc.scheduleMissedEventAlert(for: event)
                }
            }

            if edit.done == true {
                event.status = .completed
                svc.cancelEventNotifications(for: event)   // no reminders for finished work
            }

            summaries.append("\(event.title): \(edit.summary)")
        }

        try? context.save()
        WidgetSync.refresh()
        return summaries
    }
}
