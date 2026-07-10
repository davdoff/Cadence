import SwiftUI
import SwiftData

/// The "Ask AI" secretary box (ai-planner.md). One natural-language field;
/// the server classifies the intent and returns a typed AssistantDecision.
/// Every mutating intent is previewed here and confirmed before anything
/// is written — nothing happens behind the user's back.
struct AIInputView: View {
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Event.startTime) private var allEvents: [Event]
    @Query private var prefsResults: [UserPreferences]
    @Query private var categories: [Category]

    @State private var description = ""
    @State private var isLoading = false
    @State private var decision: AssistantDecision?
    @State private var errorMessage: String?
    // The text that produced a clarify question — answers are appended to it.
    @State private var clarifyBase: String?
    @State private var showPlanSheet = false

    private static let exampleChips = [
        "move my gym to tomorrow morning",
        "find me 2h for taxes this week",
        "clean up my afternoon",
        "plan my week's workouts",
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                theme.backgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        inputRow
                        planPeriodButton

                        if isLoading {
                            loadingView
                        } else if let decision {
                            resultView(for: decision)
                        } else if let error = errorMessage {
                            errorView(error)
                        } else {
                            hintView
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Ask AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(theme.accent)
                }
            }
            .sheet(isPresented: $showPlanSheet) {
                GeneratePlanSheet { interpretation, drafts in
                    // Hand the plan to the existing generate confirm card —
                    // the insert still only happens on the user's confirm.
                    decision = .generate(interpretation: interpretation, events: drafts)
                    errorMessage = nil
                }
            }
        }
    }

    /// Structured entry to /v1/schedule/generate — for "fill this period"
    /// requests where an explicit date range beats free text.
    private var planPeriodButton: some View {
        Button { showPlanSheet = true } label: {
            Label("Plan a period…", systemImage: "wand.and.stars")
                .font(.caption.weight(.semibold))
                .foregroundColor(theme.accent)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(theme.cardSurface)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .disabled(isLoading)
    }

    // MARK: - Input row

    private var inputRow: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("e.g. move my gym to tomorrow morning", text: $description, axis: .vertical)
                .lineLimit(1...4)
                .padding(12)
                .cardStyle()

            Button { submit(description) } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 38))
                    .foregroundColor(canSubmit ? theme.accent : theme.light)
            }
            .disabled(!canSubmit || isLoading)
        }
    }

    private var canSubmit: Bool {
        !description.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Result views

    @ViewBuilder
    private func resultView(for decision: AssistantDecision) -> some View {
        switch decision {
        case .add(let interpretation, let event, let conflictReason, let alternatives):
            if let reason = conflictReason, !reason.isEmpty {
                conflictCard(interpretation: interpretation, reason: reason, alternatives: alternatives)
            } else if let event {
                addConfirmCard(interpretation: interpretation, draft: event)
            } else {
                suggestCard(interpretation: interpretation, alternatives)
            }
        case .move(let interpretation, let id, let newStart, let newEnd, let alternatives):
            moveCard(interpretation: interpretation, targetID: id,
                     newStart: newStart, newEnd: newEnd, alternatives: alternatives,
                     label: "Move")
        case .reschedule(let interpretation, let id, let newStart, let newEnd):
            moveCard(interpretation: interpretation, targetID: id,
                     newStart: newStart, newEnd: newEnd, alternatives: [],
                     label: "Reschedule")
        case .reorganize(let interpretation, let moves, let displaced):
            reorganizeCard(interpretation: interpretation, moves: moves, displaced: displaced)
        case .generate(let interpretation, let events):
            generateCard(interpretation: interpretation, drafts: events)
        case .clarify(let question, let options):
            clarifyCard(question: question, options: options)
        }
    }

    /// The one-sentence echo shown at the top of every decision card.
    private func interpretationHeader(_ text: String, icon: String = "sparkles") -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundColor(theme.accent)
    }

    private func addConfirmCard(interpretation: String, draft: EventDraft) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            interpretationHeader(interpretation)

            VStack(alignment: .leading, spacing: 6) {
                Text(draft.title)
                    .font(.headline)
                Text(formatSlot(start: draft.start, end: draft.end))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                if !draft.categoryName.isEmpty {
                    Text(draft.categoryName)
                        .font(.caption)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(theme.light.opacity(0.25))
                        .clipShape(Capsule())
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            confirmButton("Confirm & Add") { insertDrafts([draft]) }
        }
        .padding()
        .background(theme.deep)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func conflictCard(interpretation: String, reason: String, alternatives: [EventDraft]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(interpretation, systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundColor(.orange)

            Text(reason)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.cardSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            if !alternatives.isEmpty {
                Text("Available slots")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                // Keep the server's title; insertDrafts falls back to the
                // typed request only when it's empty (UI_REVIEW §1.4).
                ForEach(Array(alternatives.enumerated()), id: \.offset) { _, slot in
                    slotButton(slot)
                }
            }
        }
        .padding()
        .background(theme.deep)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func suggestCard(interpretation: String, _ drafts: [EventDraft]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            interpretationHeader(interpretation)

            ForEach(Array(drafts.enumerated()), id: \.offset) { _, draft in
                slotButton(draft)
            }
        }
        .padding()
        .background(theme.deep)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    /// Shared preview for move and reschedule: old time → new time + confirm.
    private func moveCard(
        interpretation: String, targetID: UUID,
        newStart: Date, newEnd: Date, alternatives: [EventDraft], label: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            interpretationHeader(interpretation, icon: "arrow.uturn.right")

            if let event = allEvents.first(where: { $0.id == targetID }) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(event.title)
                        .font(.headline)
                    Text(formatSlot(start: event.startTime, end: event.endTime))
                        .font(.subheadline)
                        .strikethrough()
                        .foregroundColor(.secondary)
                    Text(formatSlot(start: newStart, end: newEnd))
                        .font(.subheadline.weight(.semibold))
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.cardSurface)
                .clipShape(RoundedRectangle(cornerRadius: 14))

                confirmButton("Confirm \(label)") {
                    applyMoves([PlannedMove(targetEventID: targetID, newStart: newStart, newEnd: newEnd)])
                }

                if !alternatives.isEmpty {
                    Text("Other options")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    ForEach(Array(alternatives.enumerated()), id: \.offset) { _, slot in
                        Button {
                            applyMoves([PlannedMove(targetEventID: targetID, newStart: slot.start, newEnd: slot.end)])
                        } label: {
                            slotLabel(start: slot.start, end: slot.end)
                        }
                    }
                }
            } else {
                Text("That event is no longer on your schedule.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(theme.deep)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func reorganizeCard(interpretation: String, moves: [PlannedMove], displaced: [UUID]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            interpretationHeader(interpretation, icon: "arrow.triangle.2.circlepath")

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(moves.enumerated()), id: \.offset) { _, move in
                    if let event = allEvents.first(where: { $0.id == move.targetEventID }) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title).font(.subheadline.weight(.semibold))
                            Text("\(formatSlot(start: event.startTime, end: event.endTime)) → \(formatSlot(start: move.newStart, end: move.newEnd))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                if !displaced.isEmpty {
                    Divider()
                    Text("Set aside for later (moved to Needs rescheduling):")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.orange)
                    ForEach(displaced, id: \.self) { id in
                        if let event = allEvents.first(where: { $0.id == id }) {
                            Text(event.title)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            confirmButton("Apply Changes") { applyMoves(moves, displacing: displaced) }
        }
        .padding()
        .background(theme.deep)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func generateCard(interpretation: String, drafts: [EventDraft]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            interpretationHeader(interpretation, icon: "wand.and.stars")

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(drafts.enumerated()), id: \.offset) { _, draft in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(draft.title).font(.subheadline.weight(.semibold))
                        Text(formatSlot(start: draft.start, end: draft.end))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            confirmButton("Add All (\(drafts.count))") { insertDrafts(drafts) }
        }
        .padding()
        .background(theme.deep)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func clarifyCard(question: String, options: [String]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(question, systemImage: "questionmark.circle.fill")
                .font(.subheadline.weight(.semibold))

            ForEach(options, id: \.self) { option in
                Button {
                    answerClarify(option)
                } label: {
                    HStack {
                        Text(option).foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.circle")
                            .foregroundColor(theme.accent)
                    }
                    .padding()
                    .background(theme.cardSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }

            Text("Or refine your request above and send again.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(theme.deep)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func confirmButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(theme.accentGradient)
            .foregroundColor(.white)
            .font(.subheadline.weight(.semibold))
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func slotButton(_ draft: EventDraft) -> some View {
        Button { insertDrafts([draft]) } label: {
            slotLabel(start: draft.start, end: draft.end)
        }
    }

    private func slotLabel(start: Date, end: Date) -> some View {
        HStack {
            Image(systemName: "clock")
                .foregroundColor(theme.accent)
            Text(formatSlot(start: start, end: end))
                .foregroundColor(.primary)
            Spacer()
            Image(systemName: "plus.circle.fill")
                .foregroundColor(theme.accent)
        }
        .padding()
        .background(theme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Loading / hint / error

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView().tint(theme.accent).scaleEffect(1.4)
            Text("Thinking…")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }

    private var hintView: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundColor(theme.light)
            Text("Your scheduling secretary: add, move, or reorganize events, or plan whole goals — in plain language.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            FlowChips(items: Self.exampleChips) { chip in
                description = chip
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 40))
                .foregroundColor(.red.opacity(0.6))
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }

    // MARK: - Actions

    private func submit(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        decision = nil
        errorMessage = nil
        isLoading = true

        let service = AIService()
        let prefs   = prefsResults.first ?? UserPreferences()
        let events  = allEvents
        let cats    = Array(categories)

        Task {
            do {
                let result = try await service.interpret(
                    text: trimmed,
                    events: events,
                    preferences: prefs,
                    categories: cats
                )
                await MainActor.run {
                    if case .clarify = result {
                        // Remember what produced the question so answers extend it.
                        if clarifyBase == nil { clarifyBase = trimmed }
                    } else {
                        clarifyBase = nil
                    }
                    decision = result
                    isLoading = false
                }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription; isLoading = false }
            }
        }
    }

    /// The server is stateless, so a clarify answer is folded into the original
    /// request text and re-interpreted as one self-contained message.
    private func answerClarify(_ answer: String) {
        let base = clarifyBase ?? description
        submit("\(base)\nAnswer to your question: \(answer)")
    }

    private func insertDrafts(_ drafts: [EventDraft]) {
        let prefs = prefsResults.first ?? UserPreferences()
        let svc = NotificationService()
        for draft in drafts {
            let matched = categories.first { $0.name.lowercased() == draft.categoryName.lowercased() }
            let event = Event(
                title: draft.title.isEmpty ? description : draft.title,
                startTime: draft.start,
                endTime: draft.end,
                category: matched,
                source: .ai
            )
            context.insert(event)
            scheduleNotifications(for: event, prefs: prefs, svc: svc)
        }
        finalize()
    }

    /// Applies confirmed moves (move / reschedule / reorganize) and marks
    /// displaced events, in one save.
    private func applyMoves(_ moves: [PlannedMove], displacing displaced: [UUID] = []) {
        let prefs = prefsResults.first ?? UserPreferences()
        let svc = NotificationService()
        for move in moves {
            guard let event = allEvents.first(where: { $0.id == move.targetEventID }) else { continue }
            svc.cancelEventNotifications(for: event)
            event.startTime = move.newStart
            event.endTime = move.newEnd
            event.status = .pending
            scheduleNotifications(for: event, prefs: prefs, svc: svc)
        }
        for id in displaced {
            guard let event = allEvents.first(where: { $0.id == id }) else { continue }
            svc.cancelEventNotifications(for: event)
            event.status = .displaced
        }
        finalize()
    }

    private func scheduleNotifications(for event: Event, prefs: UserPreferences, svc: NotificationService) {
        guard svc.isNotificationEnabled(for: event, prefs: prefs) else { return }
        event.notificationIdentifier = svc.scheduleEventReminder(
            for: event, reminderMinutes: prefs.defaultReminderMinutes
        )
        svc.scheduleEventStartAlert(for: event, reminderMinutes: prefs.defaultReminderMinutes)
        svc.scheduleMissedEventAlert(for: event)
    }

    private func finalize() {
        try? context.save()
        WidgetSync.refresh()
        dismiss()
    }

    // MARK: - Formatting

    private func formatSlot(start: Date, end: Date) -> String {
        let sf = DateFormatter(); sf.dateFormat = "EEE d MMM, h:mm a"
        let ef = DateFormatter(); ef.dateFormat = "h:mm a"
        return "\(sf.string(from: start)) – \(ef.string(from: end))"
    }
}

// MARK: - Example chips

/// Tappable example prompts that fill the input field — teaches the box's
/// range (ai-planner.md §8) without a manual.
private struct FlowChips: View {
    @Environment(\.theme) private var theme
    let items: [String]
    let onTap: (String) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ForEach(items, id: \.self) { item in
                Button { onTap(item) } label: {
                    Text("“\(item)”")
                        .font(.caption)
                        .foregroundColor(theme.accent)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(theme.cardSurface)
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
                }
            }
        }
    }
}
