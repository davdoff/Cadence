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
    // Follow-up thread for the read-only answer card: prior Q&A turns replayed to
    // the (stateless) server so refinements resolve against the last answer.
    @State private var turns: [ConversationTurn] = []
    @State private var followUpText = ""
    // Optional pre-declaration of the kind of request, so the model doesn't have
    // to infer the read-only/mutating boundary and the server can skip the context
    // the other kind would need. Auto (no hint) stays the default.
    @State private var mode: AskMode = .auto

    /// UI face of `IntentHint`, plus the "let the model decide" case.
    private enum AskMode: String, CaseIterable, Identifiable {
        case auto = "Auto"
        case ask = "Ask"
        case change = "Change"

        var id: Self { self }

        var hint: IntentHint? {
            switch self {
            case .auto:   return nil
            case .ask:    return .ask
            case .change: return .change
            }
        }

        var help: String {
            switch self {
            case .auto:   return "Cadence works out what you meant."
            case .ask:    return "Questions about your schedule — nothing is changed."
            case .change: return "Add, move, edit or cancel events."
            }
        }
    }

    private static let exampleChips = [
        "move my gym to tomorrow morning",
        "find me 2h for taxes this week",
        "clean up my afternoon",
        "mark my meetings as Work",
        "cancel my dentist appointment",
        "plan my week's workouts",
        "summarize my week",
        "when's my next gym?",
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                theme.backgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        modePicker
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

    // MARK: - Mode picker

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Kind of request", selection: $mode) {
                ForEach(AskMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(isLoading)

            Text(mode.help)
                .font(.caption2)
                .foregroundColor(theme.light)
        }
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
        case .edit(let interpretation, let edits):
            editCard(interpretation: interpretation, edits: edits)
        case .delete(let interpretation, let targetIDs):
            deleteCard(interpretation: interpretation, targetIDs: targetIDs)
        case .generate(let interpretation, let events):
            generateCard(interpretation: interpretation, drafts: events)
        case .summarize(let interpretation, let summary):
            answerCard(interpretation: interpretation, text: summary, icon: "chart.bar.doc.horizontal")
        case .query(let interpretation, let answer):
            answerCard(interpretation: interpretation, text: answer, icon: "magnifyingglass")
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
                    .foregroundColor(theme.text)
                Text(formatSlot(start: draft.start, end: draft.end))
                    .font(.subheadline)
                    .foregroundColor(theme.text2)
                if !draft.categoryName.isEmpty {
                    Text(draft.categoryName)
                        .font(.caption)
                        .foregroundColor(theme.chipText)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(theme.chipBg)
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
        .cardStyle()
    }

    private func conflictCard(interpretation: String, reason: String, alternatives: [EventDraft]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(interpretation, systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundColor(.orange)

            Text(reason)
                .font(.subheadline)
                .foregroundColor(theme.text2)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.cardSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            if !alternatives.isEmpty {
                Text("Available slots")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(theme.text2)
                // Keep the server's title; insertDrafts falls back to the
                // typed request only when it's empty (UI_REVIEW §1.4).
                ForEach(Array(alternatives.enumerated()), id: \.offset) { _, slot in
                    slotButton(slot)
                }
            }
        }
        .padding()
        .cardStyle()
    }

    private func suggestCard(interpretation: String, _ drafts: [EventDraft]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            interpretationHeader(interpretation)

            ForEach(Array(drafts.enumerated()), id: \.offset) { _, draft in
                slotButton(draft)
            }
        }
        .padding()
        .cardStyle()
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
                        .foregroundColor(theme.text)
                    Text(formatSlot(start: event.startTime, end: event.endTime))
                        .font(.subheadline)
                        .strikethrough()
                        .foregroundColor(theme.text2)
                    Text(formatSlot(start: newStart, end: newEnd))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(theme.text)
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
                        .foregroundColor(theme.text2)
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
                    .foregroundColor(theme.text2)
            }
        }
        .padding()
        .cardStyle()
    }

    private func reorganizeCard(interpretation: String, moves: [PlannedMove], displaced: [UUID]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            interpretationHeader(interpretation, icon: "arrow.triangle.2.circlepath")

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(moves.enumerated()), id: \.offset) { _, move in
                    if let event = allEvents.first(where: { $0.id == move.targetEventID }) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title).font(.subheadline.weight(.semibold))
                                .foregroundColor(theme.text)
                            Text("\(formatSlot(start: event.startTime, end: event.endTime)) → \(formatSlot(start: move.newStart, end: move.newEnd))")
                                .font(.caption)
                                .foregroundColor(theme.text2)
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
                                .foregroundColor(theme.text2)
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
        .cardStyle()
    }

    /// Preview for the "edit" intent: each event lists the specific fields that
    /// will change (title, category, time), so the user approves exactly what
    /// the AI proposes before anything is written.
    private func editCard(interpretation: String, edits: [EventEdit]) -> some View {
        // Keep only edits whose target still exists, paired with the event.
        let live: [(EventEdit, Event)] = edits.compactMap { edit in
            allEvents.first(where: { $0.id == edit.targetEventID }).map { (edit, $0) }
        }
        return VStack(alignment: .leading, spacing: 14) {
            interpretationHeader(interpretation, icon: "square.and.pencil")

            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(live.enumerated()), id: \.offset) { _, pair in
                    editRow(edit: pair.0, event: pair.1)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            if live.isEmpty {
                Text("Those events are no longer on your schedule.")
                    .font(.subheadline)
                    .foregroundColor(theme.text2)
            } else {
                confirmButton("Apply changes (\(live.count))") {
                    applyEdits(live.map(\.0))
                }
            }
        }
        .padding()
        .cardStyle()
    }

    /// One event's before/after within the edit card. Unchanged fields render
    /// plainly; changed ones show the new value (title/time struck-through old).
    @ViewBuilder
    private func editRow(edit: EventEdit, event: Event) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let newTitle = edit.title {
                Text(event.title).font(.caption).strikethrough().foregroundColor(theme.text2)
                Text(newTitle).font(.subheadline.weight(.semibold)).foregroundColor(theme.text)
            } else {
                Text(event.title).font(.subheadline.weight(.semibold)).foregroundColor(theme.text)
            }

            if edit.changesTime, let s = edit.newStart, let e = edit.newEnd {
                Text(formatSlot(start: event.startTime, end: event.endTime))
                    .font(.caption).strikethrough().foregroundColor(theme.text2)
                Text(formatSlot(start: s, end: e))
                    .font(.caption.weight(.semibold)).foregroundColor(theme.text)
            } else {
                Text(formatSlot(start: event.startTime, end: event.endTime))
                    .font(.caption).foregroundColor(theme.text2)
            }

            if let category = edit.category {
                Text("→ \(category)")
                    .font(.caption)
                    .foregroundColor(theme.chipText)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(theme.chipBg)
                    .clipShape(Capsule())
            }
        }
    }

    /// Preview for the "delete" intent: lists every event that will be removed
    /// so the user confirms exactly what disappears. Styled destructively (red)
    /// to set it apart from the additive cards.
    private func deleteCard(interpretation: String, targetIDs: [UUID]) -> some View {
        let targets = allEvents.filter { targetIDs.contains($0.id) }
        return VStack(alignment: .leading, spacing: 14) {
            Label(interpretation, systemImage: "trash.fill")
                .font(.caption.weight(.semibold))
                .foregroundColor(.red)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(targets, id: \.id) { event in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title).font(.subheadline.weight(.semibold))
                            .foregroundColor(theme.text)
                        Text(formatSlot(start: event.startTime, end: event.endTime))
                            .font(.caption)
                            .foregroundColor(theme.text2)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            if targets.isEmpty {
                Text("Those events are no longer on your schedule.")
                    .font(.subheadline)
                    .foregroundColor(theme.text2)
            } else {
                Button("Delete (\(targets.count))") {
                    applyDelete(targetIDs: targetIDs)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Color.red)
                .foregroundColor(.white)
                .font(.subheadline.weight(.semibold))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding()
        .cardStyle()
    }

    private func generateCard(interpretation: String, drafts: [EventDraft]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            interpretationHeader(interpretation, icon: "wand.and.stars")

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(drafts.enumerated()), id: \.offset) { _, draft in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(draft.title).font(.subheadline.weight(.semibold))
                            .foregroundColor(theme.text)
                        Text(formatSlot(start: draft.start, end: draft.end))
                            .font(.caption)
                            .foregroundColor(theme.text2)
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
        .cardStyle()
    }

    /// The only READ-ONLY result: an overview/analytics answer. Nothing is
    /// staged or written, so there's no confirm button and no `finalize()` —
    /// just the narrative and a way to dismiss or ask again.
    /// The read-only answer card shared by the two non-mutating intents
    /// (summarize / query). Display-only: no confirm, no finalize/save/sync.
    private func answerCard(interpretation: String, text: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            interpretationHeader(interpretation, icon: icon)

            Text(text)
                .font(.subheadline)
                .foregroundColor(theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding()
                .background(theme.cardSurface)
                .clipShape(RoundedRectangle(cornerRadius: 14))

            // Follow-up: keep this answer on screen and refine it in place. The
            // prior turn is replayed to the server so "what about…" has context.
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask a follow-up…", text: $followUpText, axis: .vertical)
                    .lineLimit(1...3)
                    .padding(10)
                    .background(theme.cardSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Button {
                    submit(followUpText, continuing: true)
                    followUpText = ""
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(canFollowUp ? theme.accent : theme.light)
                }
                .disabled(!canFollowUp || isLoading)
            }

            HStack(spacing: 10) {
                Button("Start over") {
                    decision = nil
                    description = ""
                    followUpText = ""
                    turns = []
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(theme.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(theme.cardSurface)
                .clipShape(RoundedRectangle(cornerRadius: 14))

                Button("Done") { dismiss() }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(theme.accentGradient)
                    .foregroundColor(.white)
                    .font(.subheadline.weight(.semibold))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding()
        .cardStyle()
    }

    private var canFollowUp: Bool {
        !followUpText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func clarifyCard(question: String, options: [String]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(question, systemImage: "questionmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(theme.text)

            ForEach(options, id: \.self) { option in
                Button {
                    answerClarify(option)
                } label: {
                    HStack {
                        Text(option).foregroundColor(theme.text)
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
                .foregroundColor(theme.text2)
        }
        .padding()
        .cardStyle()
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
                .foregroundColor(theme.text)
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
        AILoadingIndicator()
            .frame(maxWidth: .infinity)
            .padding(32)
    }

    private var hintView: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundColor(theme.light)
            Text("Your scheduling secretary: add, move, or reorganize events, plan whole goals, or ask how your week's looking — in plain language.")
                .font(.subheadline)
                .foregroundColor(theme.text2)
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
                .foregroundColor(theme.text2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }

    // MARK: - Actions

    /// `continuing` = a follow-up from the answer card: keep the thread and replay
    /// it as context. A fresh submit (top box / chips) starts a new thread.
    private func submit(_ text: String, continuing: Bool = false) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if !continuing { turns = [] }
        let history = turns
        decision = nil
        errorMessage = nil
        isLoading = true

        let service = AIService()
        let prefs   = prefsResults.first ?? UserPreferences()
        let events  = allEvents
        let cats    = Array(categories)
        let hint    = mode.hint

        Task {
            do {
                let result = try await service.interpret(
                    text: trimmed,
                    events: events,
                    preferences: prefs,
                    categories: cats,
                    history: history,
                    intentHint: hint
                )
                await MainActor.run {
                    if case .clarify = result {
                        // Remember what produced the question so answers extend it.
                        if clarifyBase == nil { clarifyBase = trimmed }
                    } else {
                        clarifyBase = nil
                    }
                    // Grow the follow-up thread only for read-only answers — those
                    // are the cards that expose a follow-up field.
                    if let reply = result.readOnlyReply {
                        turns.append(ConversationTurn(user: trimmed, assistant: reply))
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
        EventApplyService.insert(
            drafts, source: .ai, fallbackTitle: description,
            prefs: prefsResults.first ?? UserPreferences(),
            categories: Array(categories), context: context
        )
        finalize()
    }

    /// Applies confirmed moves (move / reschedule / reorganize) and marks
    /// displaced events, in one save.
    private func applyMoves(_ moves: [PlannedMove], displacing displaced: [UUID] = []) {
        let prefs = prefsResults.first ?? UserPreferences()
        for move in moves {
            guard let event = allEvents.first(where: { $0.id == move.targetEventID }) else { continue }
            EventApplyService.move(event, to: move.newStart, end: move.newEnd, prefs: prefs)
        }
        let svc = NotificationService()
        for id in displaced {
            guard let event = allEvents.first(where: { $0.id == id }) else { continue }
            svc.cancelEventNotifications(for: event)
            event.status = .displaced
        }
        finalize()
    }

    /// Applies confirmed per-event edits from the "edit" intent: title,
    /// category, and/or time, each only when the AI proposed a change. A time
    /// change reschedules that event's notifications and resets it to pending
    /// (like a move); title/category changes touch no notifications. All in one
    /// save.
    private func applyEdits(_ edits: [EventEdit]) {
        let prefs = prefsResults.first ?? UserPreferences()
        for edit in edits {
            guard let event = allEvents.first(where: { $0.id == edit.targetEventID }) else { continue }
            if let title = edit.title?.trimmingCharacters(in: .whitespaces), !title.isEmpty {
                event.title = title
            }
            if let name = edit.category {
                event.category = EventApplyService.resolveOrCreateCategory(
                    named: name, in: Array(categories), context: context
                )
            }
            if edit.changesTime, let newStart = edit.newStart, let newEnd = edit.newEnd {
                EventApplyService.move(event, to: newStart, end: newEnd, prefs: prefs)
            }
        }
        finalize()
    }

    /// Hard-deletes the confirmed events from the "delete" intent, mirroring the
    /// manual swipe-to-delete in ScheduleView: cancel each event's notifications
    /// and tombstone imported ones so a later calendar sync doesn't re-add them.
    private func applyDelete(targetIDs: [UUID]) {
        let svc = NotificationService()
        for event in allEvents where targetIDs.contains(event.id) {
            svc.cancelEventNotifications(for: event)
            CalendarImportService.shared.noteLocalDeletion(of: event, context: context)
            context.delete(event)
        }
        finalize()
    }

    private func finalize() {
        EventApplyService.finalize(context: context)
        dismiss()
    }

    // MARK: - Formatting

    private func formatSlot(start: Date, end: Date) -> String {
        let sf = DateFormatter(); sf.dateFormat = "EEE d MMM, h:mm a"
        let ef = DateFormatter(); ef.dateFormat = "h:mm a"
        return "\(sf.string(from: start)) – \(ef.string(from: end))"
    }
}

// MARK: - Loading indicator

/// On-brand "Thinking…" state: a themed bar that sweeps quickly to ~90% and
/// holds, over a Cadence "C" that spins while its arc grows and shrinks — so it
/// reads as the C being drawn, then flowing into the next spin. The bar stays at
/// 90% because the answer's arrival swaps this whole view out for the result card.
private struct AILoadingIndicator: View {
    @Environment(\.theme) private var theme
    @State private var progress: CGFloat = 0
    @State private var rotation: Double = 0
    @State private var trimEnd: CGFloat = 0.2

    var body: some View {
        VStack(spacing: 18) {
            // Themed progress bar, filling fast to 90% then holding.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.track)
                    Capsule()
                        .fill(theme.barGradient)
                        .frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 6)
            .frame(maxWidth: 220)

            // The Cadence "C": a rotating arc whose length pulses, so it looks
            // like the C is being built and then flows into the next load.
            Circle()
                .trim(from: 0, to: trimEnd)
                .stroke(theme.barGradient, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .frame(width: 26, height: 26)
                .rotationEffect(.degrees(rotation))

            Text("Thinking…")
                .font(.subheadline)
                .foregroundColor(theme.text2)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.75)) { progress = 0.9 }
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { rotation = 360 }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { trimEnd = 0.9 }
        }
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
