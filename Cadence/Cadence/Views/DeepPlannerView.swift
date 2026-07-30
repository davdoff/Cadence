import SwiftUI
import SwiftData

/// The Deep Planner surface — the primary half of the Overview tab (see
/// `OverviewTabView`). Turns a long-term goal into a thin whole-horizon
/// skeleton, then plans one week of focused sessions at a time, advancing on
/// completion + feedback. See `deep-planner-plan.md` for the full loop.
///
/// Increment 1: intake → skeleton + cushion. Weekly planning, the review card,
/// and multiturn intake arrive next (deep-planner-plan.md §7).
struct DeepPlannerView: View {
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var context
    @Query(sort: \ProjectPlan.createdAt, order: .reverse) private var plans: [ProjectPlan]

    @State private var showIntake = false

    private var activePlan: ProjectPlan? { plans.first }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let plan = activePlan {
                    planView(plan)
                } else {
                    emptyState
                }
            }
            .padding()
            .padding(.bottom, 20)
        }
        .toolbar {
            if activePlan != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showIntake = true } label: { Label("New plan", systemImage: "plus") }
                        if let plan = activePlan {
                            Button(role: .destructive) { context.delete(plan) } label: {
                                Label("Delete plan", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showIntake) {
            DeepPlanIntakeView()
        }
    }

    // MARK: - Active plan

    @ViewBuilder
    private func planView(_ plan: ProjectPlan) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(plan.title)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(theme.text)
                HStack(spacing: 6) {
                    Text(plan.goalType == .study ? "Study" : "Project")
                    if let deadline = plan.deadline {
                        Text("·").foregroundColor(theme.text2)
                        Text("by \(deadline.formatted(.dateTime.month().day()))")
                    }
                }
                .font(.subheadline)
                .foregroundColor(theme.text2)
            }

            cushionBadge(plan)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(plan.orderedUnits) { unitRow($0) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .cardStyle()
    }

    private func cushionBadge(_ plan: ProjectPlan) -> some View {
        let cushion = plan.cushionMinutes
        let over = cushion < 0
        return HStack(spacing: 8) {
            Image(systemName: over ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
            Text(over
                 ? "Over by \(hoursLabel(-cushion)) — cut scope or add time"
                 : "\(hoursLabel(cushion)) cushion")
                .font(.subheadline.weight(.medium))
        }
        .foregroundColor(over ? .red : .green)
        .padding(.vertical, 8).padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func unitRow(_ unit: WorkUnit) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(unit.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(theme.text)
                Spacer()
                Text(hoursLabel(unit.estimatedMinutes))
                    .font(.caption).foregroundColor(theme.text2)
            }
            Text(unit.objective)
                .font(.caption)
                .foregroundColor(theme.text2)
            HStack(spacing: 6) {
                tag(unit.archetype == .repetition ? "recall" : "milestone")
                if unit.repeatOf != nil { tag("revisit") }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Divider().opacity(unit.order == 0 ? 0 : 1) }
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundColor(theme.accent)
            .padding(.vertical, 2).padding(.horizontal, 7)
            .background(theme.accent.opacity(0.12))
            .clipShape(Capsule())
    }

    /// Minutes → "3h 30m" / "45m" / "2h".
    private func hoursLabel(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    // MARK: - Empty state (no active plan)

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "target")
                .font(.system(size: 52))
                .foregroundColor(theme.light)

            Text("Plan a goal")
                .font(.title3.weight(.semibold))
                .foregroundColor(theme.text)

            Text("Give the planner a goal — an exam, a project, a skill — and it plans one focused week at a time, adapting as you go.")
                .font(.subheadline)
                .foregroundColor(theme.text2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button {
                showIntake = true
            } label: {
                Text("Start a plan")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(theme.accentGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 24)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}
