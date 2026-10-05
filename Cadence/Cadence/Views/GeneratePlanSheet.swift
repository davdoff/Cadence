import SwiftUI
import SwiftData

/// The direct entry to /v1/schedule/generate (ai-planner.md §7): pick a
/// period, state goals, and the server fills the free slots. Standing
/// preferences (work hours, buffers, avoid-blocks, AI level) ride along
/// automatically — only the momentary intent is asked for here.
///
/// The sheet only collects input and fetches the plan; the confirm/insert
/// step stays in AIInputView's generate card, so nothing is written from here.
///
/// Templates mode (day-templates.md) is the local, zero-AI alternative: pick a
/// day template per day (or fill the days from a saved week layout), then
/// `TemplatePreviewView` shows where everything lands and does its own confirm,
/// because its per-clash "move my event instead" toggles need their own screen.
struct GeneratePlanSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Event.startTime) private var allEvents: [Event]
    @Query private var prefsResults: [UserPreferences]
    @Query private var categories: [Category]
    @Query(sort: \DayTemplate.name) private var templates: [DayTemplate]
    @Query(sort: \WeekTemplate.name) private var weekTemplates: [WeekTemplate]
    @Environment(\.modelContext) private var context

    /// Called with (interpretation, drafts) when a plan comes back non-empty.
    let onPlan: (String, [EventDraft]) -> Void

    @State private var startDate = Calendar.current.startOfDay(for: .now)
    @State private var endDate = Calendar.current.date(
        byAdding: .day, value: 6, to: Calendar.current.startOfDay(for: .now)
    )!
    @State private var goals = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    private enum Mode: String, CaseIterable, Identifiable {
        case goals = "Goals (AI)"
        case templates = "Templates"
        var id: Self { self }
    }
    @State private var mode: Mode = .goals
    /// Start-of-day → chosen DayTemplate id. Days outside the range are ignored.
    @State private var dayAssignments: [Date: UUID] = [:]
    @State private var showPreview = false
    @State private var showSaveWeek = false
    @State private var weekName = ""

    /// Longest range Templates mode lists day by day.
    private static let maxTemplateDays = 31

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
                theme.backgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Picker("Mode", selection: $mode) {
                            ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .disabled(isLoading)

                        quickRangeRow
                        periodCard

                        switch mode {
                        case .goals:
                            goalsCard

                            if let error = errorMessage {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            generateButton
                        case .templates:
                            templatesCard
                            previewButton
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Plan a Period")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showPreview) {
                TemplatePreviewView(assignments: chosenAssignments) { dismiss() }
            }
            .alert("Save week layout", isPresented: $showSaveWeek) {
                TextField("Name", text: $weekName)
                Button("Save") { saveWeekLayout() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Remembers which template each weekday uses, to fill any week in one tap.")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(theme.accent)
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
                            .foregroundColor(isSelected(range) ? .white : theme.accent)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(isSelected(range) ? AnyShapeStyle(theme.accentGradient) : AnyShapeStyle(theme.cardSurface))
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
        .cardStyle()
    }

    private var goalsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What should this period achieve?")
                .font(.caption.weight(.semibold))
                .foregroundColor(theme.text2)
            TextField("e.g. 3 workouts and 4h of exam prep, evenings preferred", text: $goals, axis: .vertical)
                .lineLimit(2...5)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
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
        .background(canSubmit ? AnyShapeStyle(theme.accentGradient) : AnyShapeStyle(theme.light))
        .foregroundColor(.white)
        .font(.subheadline.weight(.semibold))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .disabled(!canSubmit || isLoading)
    }

    private var canSubmit: Bool {
        !goals.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Templates mode

    /// Each day in the picked range (capped), as start-of-day dates.
    private var rangeDays: [Date] {
        let cal = Calendar.current
        let first = cal.startOfDay(for: startDate)
        let last = cal.startOfDay(for: endDate)
        var days: [Date] = []
        var day = first
        while day <= last && days.count < Self.maxTemplateDays {
            days.append(day)
            day = cal.date(byAdding: .day, value: 1, to: day)!
        }
        return days
    }

    /// The days that have a template picked, paired with it, in date order.
    private var chosenAssignments: [(day: Date, template: DayTemplate)] {
        rangeDays.compactMap { day in
            guard let id = dayAssignments[day],
                  let template = templates.first(where: { $0.id == id }) else { return nil }
            return (day: day, template: template)
        }
    }

    @ViewBuilder
    private var templatesCard: some View {
        if templates.isEmpty {
            Text("No day templates yet. Create one in Settings › Scheduling › Day templates.")
                .font(.caption)
                .foregroundColor(theme.text2)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Template per day")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(theme.text2)
                    Spacer()
                    weekLayoutMenu
                }
                ForEach(rangeDays, id: \.self) { day in
                    HStack {
                        Text(TemplatePreviewView.dayLabel(day))
                            .font(.subheadline)
                        Spacer()
                        Picker("Template", selection: assignmentBinding(for: day)) {
                            Text("None").tag(UUID?.none)
                            ForEach(templates) { Text($0.name).tag(UUID?.some($0.id)) }
                        }
                        .pickerStyle(.menu)
                        .tint(theme.accent)
                    }
                }
                if Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0 >= Self.maxTemplateDays {
                    Text("Showing the first \(Self.maxTemplateDays) days.")
                        .font(.caption2).foregroundColor(theme.text2)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
    }

    private var weekLayoutMenu: some View {
        Menu {
            if !weekTemplates.isEmpty {
                Section("Fill from week layout") {
                    ForEach(weekTemplates) { week in
                        Button(week.name) { fill(from: week) }
                    }
                }
            }
            Button {
                weekName = ""
                showSaveWeek = true
            } label: {
                Label("Save as week layout", systemImage: "square.and.arrow.down")
            }
            .disabled(chosenAssignments.isEmpty)
            Button(role: .destructive) { dayAssignments = [:] } label: {
                Label("Clear all", systemImage: "xmark")
            }
        } label: {
            Label("Week layout", systemImage: "calendar")
                .font(.caption.weight(.semibold))
                .foregroundColor(theme.accent)
        }
    }

    private var previewButton: some View {
        Button {
            showPreview = true
        } label: {
            Text("Preview")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
        }
        .background(chosenAssignments.isEmpty ? AnyShapeStyle(theme.light) : AnyShapeStyle(theme.accentGradient))
        .foregroundColor(.white)
        .font(.subheadline.weight(.semibold))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .disabled(chosenAssignments.isEmpty)
    }

    private func assignmentBinding(for day: Date) -> Binding<UUID?> {
        Binding(
            get: { dayAssignments[day] },
            set: { dayAssignments[day] = $0 }
        )
    }

    /// Sets every day in the range from the layout's weekday mapping; weekdays
    /// the layout leaves empty (or whose template was deleted) become None.
    private func fill(from week: WeekTemplate) {
        let cal = Calendar.current
        for day in rangeDays {
            let id = week.templateID(forWeekday: cal.component(.weekday, from: day))
            dayAssignments[day] = templates.contains(where: { $0.id == id }) ? id : nil
        }
    }

    /// Stores the current picks as a weekday pattern. When the range holds the
    /// same weekday twice, the first one wins.
    private func saveWeekLayout() {
        let cal = Calendar.current
        var assignments: [WeekdayAssignment] = []
        for (day, template) in chosenAssignments {
            let weekday = cal.component(.weekday, from: day)
            guard !assignments.contains(where: { $0.weekday == weekday }) else { continue }
            assignments.append(WeekdayAssignment(weekday: weekday, templateID: template.id))
        }
        let trimmed = weekName.trimmingCharacters(in: .whitespaces)
        context.insert(WeekTemplate(name: trimmed.isEmpty ? "Week layout" : trimmed, assignments: assignments))
        try? context.save()
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
