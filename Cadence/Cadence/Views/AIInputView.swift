import SwiftUI
import SwiftData

struct AIInputView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Event.startTime) private var allEvents: [Event]
    @Query private var prefsResults: [UserPreferences]
    @Query private var categories: [Category]

    @State private var description = ""
    @State private var isLoading = false
    @State private var decision: SchedulingDecision?
    @State private var errorMessage: String?

    private var apiKey: String {
        Bundle.main.object(forInfoDictionaryKey: "ANTHROPIC_API_KEY") as? String ?? ""
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.cadenceCream.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        inputRow

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
                        .foregroundColor(.cadenceOrange)
                }
            }
        }
    }

    // MARK: - Input row

    private var inputRow: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("e.g. dentist tomorrow at 2pm for an hour", text: $description, axis: .vertical)
                .lineLimit(1...4)
                .padding(12)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.04), radius: 4, y: 2)

            Button(action: submit) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 38))
                    .foregroundColor(canSubmit ? .cadenceOrange : .cadenceOrangeLight)
            }
            .disabled(!canSubmit || isLoading)
        }
    }

    private var canSubmit: Bool {
        !description.trimmingCharacters(in: .whitespaces).isEmpty && !apiKey.isEmpty
    }

    // MARK: - Result views

    @ViewBuilder
    private func resultView(for decision: SchedulingDecision) -> some View {
        switch decision {
        case .add(let draft):
            addConfirmCard(draft)
        case .conflict(let reason, let alternatives):
            conflictCard(reason: reason, alternatives: alternatives)
        case .suggestAlternative(let drafts):
            suggestCard(drafts)
        }
    }

    private func addConfirmCard(_ draft: EventDraft) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("AI Suggestion", systemImage: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundColor(.cadenceOrange)

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
                        .background(Color.cadenceOrangeLight.opacity(0.25))
                        .clipShape(Capsule())
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            Button("Confirm & Add") { insertDraft(draft) }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Color.cadenceOrange)
                .foregroundColor(.white)
                .font(.subheadline.weight(.semibold))
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .padding()
        .background(Color.cadenceCreamDeep)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func conflictCard(reason: String, alternatives: [EventDraft]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Conflict Detected", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundColor(.orange)

            Text(reason)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            if !alternatives.isEmpty {
                Text("Available slots")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                ForEach(Array(alternatives.enumerated()), id: \.offset) { _, slot in
                    slotButton(EventDraft(title: description, start: slot.start, end: slot.end, categoryName: ""))
                }
            }
        }
        .padding()
        .background(Color.cadenceCreamDeep)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func suggestCard(_ drafts: [EventDraft]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Suggested Slots", systemImage: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundColor(.cadenceOrange)

            ForEach(Array(drafts.enumerated()), id: \.offset) { _, draft in
                slotButton(EventDraft(title: description, start: draft.start, end: draft.end, categoryName: draft.categoryName))
            }
        }
        .padding()
        .background(Color.cadenceCreamDeep)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func slotButton(_ draft: EventDraft) -> some View {
        Button { insertDraft(draft) } label: {
            HStack {
                Image(systemName: "clock")
                    .foregroundColor(.cadenceOrange)
                Text(formatSlot(start: draft.start, end: draft.end))
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.cadenceOrange)
            }
            .padding()
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Loading / hint / error

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView().tint(.cadenceOrange).scaleEffect(1.4)
            Text("Thinking…")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }

    private var hintView: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundColor(.cadenceOrangeLight)
            Text("Describe an event in plain language and AI will find the best slot.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            if apiKey.isEmpty {
                Text("ANTHROPIC_API_KEY not set in Info.plist")
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(32)
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

    private func submit() {
        guard canSubmit else { return }
        decision = nil
        errorMessage = nil
        isLoading = true

        let service = AIService(apiKey: apiKey)
        let prefs   = prefsResults.first ?? UserPreferences()
        let events  = allEvents
        let cats    = Array(categories)

        Task {
            do {
                let result = try await service.scheduleEvent(
                    description: description,
                    events: events,
                    preferences: prefs,
                    categories: cats
                )
                await MainActor.run { decision = result; isLoading = false }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription; isLoading = false }
            }
        }
    }

    private func insertDraft(_ draft: EventDraft) {
        let matched = categories.first { $0.name.lowercased() == draft.categoryName.lowercased() }
        context.insert(Event(
            title: draft.title.isEmpty ? description : draft.title,
            startTime: draft.start,
            endTime: draft.end,
            category: matched,
            source: .ai
        ))
        try? context.save()
        dismiss()
    }

    // MARK: - Formatting

    private func formatSlot(start: Date, end: Date) -> String {
        let sf = DateFormatter(); sf.dateFormat = "EEE d MMM, h:mm a"
        let ef = DateFormatter(); ef.dateFormat = "h:mm a"
        return "\(sf.string(from: start)) – \(ef.string(from: end))"
    }
}
