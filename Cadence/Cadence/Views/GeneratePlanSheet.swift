import SwiftUI
import SwiftData

/// The direct entry to /v1/schedule/generate (ai-planner.md §7): pick a
/// period, state goals, and the server fills the free slots. Standing
/// preferences (work hours, buffers, avoid-blocks, AI level) ride along
/// automatically — only the momentary intent is asked for here.
///
/// The sheet only collects input and fetches the plan; the confirm/insert
/// step stays in AIInputView's generate card, so nothing is written from here.
struct GeneratePlanSheet: View {
    @AppStorage("accentColorHex") private var accentColorHex = "#E8784D"
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Event.startTime) private var allEvents: [Event]
    @Query private var prefsResults: [UserPreferences]
    @Query private var categories: [Category]

    /// Called with (interpretation, drafts) when a plan comes back non-empty.
    let onPlan: (String, [EventDraft]) -> Void

    @State private var startDate = Calendar.current.startOfDay(for: .now)
    @State private var endDate = Calendar.current.date(
        byAdding: .day, value: 6, to: Calendar.current.startOfDay(for: .now)
    )!
    @State private var goals = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    private struct QuickRange {
        let label: String
        let start: Date
        let end: Date
    }

    private var quickRanges: [QuickRange] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        // Strictly-after search: on a Monday this is next week's Monday,
        // so "This week" below always ends on the coming Sunday.
        let nextMonday = cal.nextDate(
            after: today, matching: DateComponents(weekday: 2), matchingPolicy: .nextTime
        ) ?? cal.date(byAdding: .day, value: 7, to: today)!
        return [
            QuickRange(label: "Today", start: today, end: today),
            QuickRange(label: "This week", start: today, end: cal.date(byAdding: .day, value: -1, to: nextMonday)!),
            QuickRange(label: "Next 7 days", start: today, end: cal.date(byAdding: .day, value: 6, to: today)!),
            QuickRange(label: "Next week", start: nextMonday, end: cal.date(byAdding: .day, value: 6, to: nextMonday)!),
        ]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground(accentColorHex).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        quickRangeRow
                        periodCard
                        goalsCard

                        if let error = errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        generateButton
                    }
                    .padding()
                }
            }
            .navigationTitle("Plan a Period")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.appAccent(accentColorHex))
                }
            }
        }
    }

    // MARK: - Sections

    private var quickRangeRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(quickRanges, id: \.label) { range in
                    Button {
                        startDate = range.start
                        endDate = range.end
                    } label: {
                        Text(range.label)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(isSelected(range) ? .white : .appAccent(accentColorHex))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(isSelected(range) ? Color.appAccent(accentColorHex) : Color.white)
                            .clipShape(Capsule())
                            .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
                    }
                }
            }
        }
    }

    private func isSelected(_ range: QuickRange) -> Bool {
        let cal = Calendar.current
        return cal.isDate(startDate, inSameDayAs: range.start) && cal.isDate(endDate, inSameDayAs: range.end)
    }

    private var periodCard: some View {
        VStack(spacing: 0) {
            DatePicker("From", selection: $startDate, in: Calendar.current.startOfDay(for: .now)..., displayedComponents: [.date])
            Divider().padding(.vertical, 8)
            DatePicker("To", selection: $endDate, in: startDate..., displayedComponents: [.date])
        }
        .padding()
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }

    private var goalsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What should this period achieve?")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            TextField("e.g. 3 workouts and 4h of exam prep, evenings preferred", text: $goals, axis: .vertical)
                .lineLimit(2...5)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }

    private var generateButton: some View {
        Button {
            submit()
        } label: {
            if isLoading {
                ProgressView().tint(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            } else {
                Text("Generate Plan")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            }
        }
        .background(canSubmit ? Color.appAccent(accentColorHex) : Color.accentLight(accentColorHex))
        .foregroundColor(.white)
        .font(.subheadline.weight(.semibold))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .disabled(!canSubmit || isLoading)
    }

    private var canSubmit: Bool {
        !goals.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Actions

    private func submit() {
        let trimmedGoals = goals.trimmingCharacters(in: .whitespaces)
        guard !trimmedGoals.isEmpty else { return }
        errorMessage = nil
        isLoading = true

        let cal = Calendar.current
        let periodStart = cal.startOfDay(for: startDate)
        // 23:59 on the last picked day — the server treats the end loosely
        // per-day, so an exclusive next-midnight bound would add a whole day.
        let periodEnd = cal.date(bySettingHour: 23, minute: 59, second: 0, of: endDate)!

        let service = AIService()
        let prefs   = prefsResults.first ?? UserPreferences()
        let events  = allEvents
        let cats    = Array(categories)

        Task {
            do {
                let drafts = try await service.generate(
                    periodStart: periodStart,
                    periodEnd: periodEnd,
                    goals: trimmedGoals,
                    events: events,
                    preferences: prefs,
                    categories: cats
                )
                await MainActor.run {
                    isLoading = false
                    if drafts.isEmpty {
                        errorMessage = "Nothing fit in that period — try a wider range or fewer goals."
                    } else {
                        onPlan(interpretation(for: drafts), drafts)
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription; isLoading = false }
            }
        }
    }

    private func interpretation(for drafts: [EventDraft]) -> String {
        let f = DateFormatter(); f.dateFormat = "EEE d MMM"
        let range = "\(f.string(from: startDate)) – \(f.string(from: endDate))"
        return "Planned \(drafts.count) event\(drafts.count == 1 ? "" : "s"), \(range)"
    }
}
