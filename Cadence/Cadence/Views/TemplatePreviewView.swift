import SwiftUI
import SwiftData

/// Preview + confirm for applying day templates (day-templates.md). Shows, per
/// day, where every block lands: unchanged, shifted around an existing event,
/// or skipped for lack of room. Each clash offers "Move <event> instead", which
/// re-runs `TemplatePlanner` so the block keeps its template time and the
/// existing event slides instead. Nothing is written until Confirm.
struct TemplatePreviewView: View {
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var context
    @Query(sort: \Event.startTime) private var allEvents: [Event]
    @Query private var prefsResults: [UserPreferences]
    @Query private var categories: [Category]

    /// The chosen template for each day, in date order.
    let assignments: [(day: Date, template: DayTemplate)]
    /// Called after the events are written, to close the whole sheet.
    let onDone: () -> Void

    @State private var moveExisting: Set<UUID> = []
    /// Fixed when the screen opens, so the plan doesn't shift while it's read.
    @State private var now = Date.now

    private var prefs: UserPreferences { prefsResults.first ?? UserPreferences() }

    private var existing: [TemplatePlanner.ExistingItem] {
        TemplatePlanner.existingItems(from: allEvents)
    }

    private var plans: [TemplatePlanner.DayPlan] {
        TemplatePlanner.planPeriod(
            assignments: assignments.map { (day: $0.day, blocks: $0.template.blocks) },
            existing: existing,
            moveExisting: moveExisting,
            bufferMinutes: prefs.bufferMinutes,
            notBefore: now
        )
    }

    var body: some View {
        let plans = self.plans
        let existingByID = Dictionary(self.existing.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let placedCount = plans.reduce(0) { $0 + $1.placedBlocks.count }

        return ZStack {
            theme.backgroundGradient.ignoresSafeArea()
            List {
                ForEach(Array(plans.enumerated()), id: \.offset) { index, plan in
                    Section {
                        daySection(plan, existingByID: existingByID)
                    } header: {
                        Text("\(Self.dayLabel(plan.day)) · \(assignments[index].template.name)")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .safeAreaInset(edge: .bottom) {
                confirmButton(count: placedCount, plans: plans)
                    .padding()
            }
        }
        .navigationTitle("Preview")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Rows

    @ViewBuilder
    private func daySection(_ plan: TemplatePlanner.DayPlan,
                            existingByID: [UUID: TemplatePlanner.ExistingItem]) -> some View {
        let toggles = Self.toggleIDs(for: plan, existingByID: existingByID, now: now)
        ForEach(Array(plan.blocks.enumerated()), id: \.offset) { index, planned in
            VStack(alignment: .leading, spacing: 6) {
                blockRow(planned, existingByID: existingByID)
                ForEach(toggles[index], id: \.self) { id in
                    if let item = existingByID[id] {
                        moveToggle(item, plan: plan)
                    }
                }
            }
            .padding(.vertical, 2)
            .listRowBackground(theme.cardSurface)
        }
    }

    /// Which "move instead" toggles to show under each block: the existing
    /// events clashing with it, each offered only once per day (an event can
    /// clash with two blocks), and never for events already in the past.
    static func toggleIDs(for plan: TemplatePlanner.DayPlan,
                          existingByID: [UUID: TemplatePlanner.ExistingItem],
                          now: Date) -> [[UUID]] {
        var offered = Set<UUID>()
        return plan.blocks.map { planned in
            planned.clashesWith.filter { id in
                guard !offered.contains(id), let item = existingByID[id], item.start >= now else { return false }
                offered.insert(id)
                return true
            }
        }
    }

    private func blockRow(_ planned: TemplatePlanner.PlannedBlock,
                          existingByID: [UUID: TemplatePlanner.ExistingItem]) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(planned.block.title).font(.subheadline.weight(.medium))
                switch planned.outcome {
                case .asIs:
                    Text(Self.range(planned.start, planned.end))
                        .font(.caption).foregroundColor(.secondary)
                case .shifted(let from):
                    Text("\(Self.time(from)) → \(Self.range(planned.start, planned.end))")
                        .font(.caption.weight(.semibold)).foregroundColor(theme.accent)
                    let names = planned.clashesWith.compactMap { existingByID[$0]?.title }
                    if !names.isEmpty {
                        Text("Moved to avoid \(names.joined(separator: ", "))")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                case .unplaceable:
                    Text("No free time that day — skipped")
                        .font(.caption).foregroundColor(.red)
                }
            }
            Spacer()
            if case .unplaceable = planned.outcome {
                Image(systemName: "xmark.circle").foregroundColor(.red)
            } else if case .shifted = planned.outcome {
                Image(systemName: "arrow.right.circle").foregroundColor(theme.accent)
            }
        }
    }

    private func moveToggle(_ item: TemplatePlanner.ExistingItem, plan: TemplatePlanner.DayPlan) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(isOn: Binding(
                get: { moveExisting.contains(item.id) },
                set: { on in
                    if on { moveExisting.insert(item.id) } else { moveExisting.remove(item.id) }
                }
            )) {
                Text("Move \(item.title) instead").font(.caption)
            }
            .tint(theme.accent)

            if let move = plan.moves.first(where: { $0.eventID == item.id }) {
                Text("\(item.title): \(Self.time(item.start)) → \(Self.range(move.newStart, move.newEnd))")
                    .font(.caption2.weight(.semibold)).foregroundColor(theme.accent)
            } else if plan.unmovable.contains(item.id) {
                Text("No free time to move it — it stays where it is")
                    .font(.caption2).foregroundColor(.red)
            }
            if item.isRecurring {
                Text("Only this occurrence moves").font(.caption2).foregroundColor(.secondary)
            } else if item.isImported {
                Text("Calendar event — Cadence keeps the new time on re-sync")
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding(.leading, 8)
    }

    private func confirmButton(count: Int, plans: [TemplatePlanner.DayPlan]) -> some View {
        Button { apply(plans) } label: {
            Text(count == 0 ? "Nothing to add" : "Add \(count) event\(count == 1 ? "" : "s")")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
        }
        .background(count > 0 ? AnyShapeStyle(theme.accentGradient) : AnyShapeStyle(theme.light))
        .foregroundColor(.white)
        .font(.subheadline.weight(.semibold))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .disabled(count == 0)
    }

    // MARK: - Apply

    private func apply(_ plans: [TemplatePlanner.DayPlan]) {
        let drafts = plans.flatMap { plan in
            plan.placedBlocks.map {
                EventDraft(title: $0.block.title, start: $0.start, end: $0.end, categoryName: $0.block.categoryName)
            }
        }
        EventApplyService.insert(drafts, source: .template, prefs: prefs,
                                 categories: Array(categories), context: context)
        for move in plans.flatMap(\.moves) {
            guard let event = allEvents.first(where: { $0.id == move.eventID }) else { continue }
            EventApplyService.move(event, to: move.newStart, end: move.newEnd, prefs: prefs)
        }
        for entry in assignments { entry.template.lastUsedDate = .now }
        EventApplyService.finalize(context: context)
        onDone()
    }

    // MARK: - Formatting

    static func dayLabel(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEE d MMM"
        return f.string(from: date)
    }

    static func time(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    static func range(_ start: Date, _ end: Date) -> String {
        "\(time(start))–\(time(end))"
    }
}
