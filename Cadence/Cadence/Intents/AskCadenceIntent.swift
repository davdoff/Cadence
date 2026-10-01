import AppIntents
import SwiftData
import Foundation

// APP TARGET ONLY — never add this file to the widget extension. It calls
// `AIService` (network + app-only types); the widget process must not.
//
// Phase 0 of the Siri spike (CADENCE_README §12): read-only voice. Siri
// dictates a question, the intent hands it to the existing `interpret()` brain
// and speaks back what comes out. No SwiftData writes, no new prompts, no
// parsing — `AIService` stays detached and this intent is the only glue.

/// "Hey Siri, ask Cadence what's on my afternoon" — runs in the background
/// (the app never opens) and speaks the assistant's reply.
struct AskCadenceIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Cadence"
    static let description = IntentDescription(
        "Ask Cadence about your schedule and hear the answer, without opening the app."
    )

    /// Background execution is the whole point of the Siri path.
    static let openAppWhenRun: Bool = false

    @Parameter(
        title: "Question",
        requestValueDialog: IntentDialog("What do you want to ask Cadence?")
    )
    var question: String

    init() {}
    init(question: String) { self.question = question }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .result(dialog: "I didn't catch a question — try asking again.")
        }

        let context = SharedModelContainer.shared.mainContext
        let events = (try? context.fetch(FetchDescriptor<Event>())) ?? []
        let categories = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        let preferences = (try? context.fetch(FetchDescriptor<UserPreferences>()))?.first
            ?? UserPreferences()

        do {
            // Race the round-trip against our own deadline. `AIService` uses
            // URLSession's default 60s timeout and the server only reports
            // TIMEOUT after a much longer SDK-level timeout — both far past
            // the ~30s budget iOS gives a background intent. Without this,
            // a stalled backend means Siri speaks its own generic failure
            // instead of ours. Kept local to the intent so `AIService` stays
            // detached. `nil` == we hit the deadline first.
            let spoken: String? = try await withThrowingTaskGroup(of: String?.self) { group in
                group.addTask { @MainActor in
                    let decision = try await AIService().interpret(
                        text: trimmed,
                        events: events,
                        preferences: preferences,
                        categories: categories
                    )
                    // Read-only cases (.query / .summarize) carry a ready-made
                    // spoken answer. Everything else — including .clarify's
                    // follow-up question — falls back to the interpretation and
                    // changes nothing (mutations are Phase 2).
                    return decision.readOnlyReply ?? decision.interpretation
                }
                group.addTask {
                    try? await Task.sleep(nanoseconds: 20_000_000_000) // 20s
                    return nil
                }
                // First finisher wins; the loser is cancelled when this scope
                // exits (URLSession's async API and Task.sleep both honour
                // cancellation), so nothing keeps running behind our answer.
                let first = try await group.next() ?? nil
                group.cancelAll()
                return first
            }

            guard let spoken else {
                return .result(dialog: "Cadence took too long to answer — try again in a moment.")
            }
            return .result(dialog: IntentDialog(stringLiteral: spoken))
        } catch {
            // Never rethrow: a thrown error makes Siri say its own generic
            // failure line instead of ours.
            if let aiError = error as? AIServiceError, case .serverError(let code, _) = aiError {
                if code == "TIMEOUT" {
                    return .result(dialog: "Cadence took too long to answer — try again in a moment.")
                }
                // The server *was* reached (AI_UNPARSEABLE / AI_UPSTREAM / …),
                // so "couldn't reach Cadence" would be misleading — speak the
                // per-code copy AIServiceError already carries.
                return .result(dialog: IntentDialog(stringLiteral:
                    aiError.errorDescription ?? "I couldn't reach Cadence right now — try again in a moment."))
            }
            return .result(dialog: "I couldn't reach Cadence right now — try again in a moment.")
        }
    }
}
