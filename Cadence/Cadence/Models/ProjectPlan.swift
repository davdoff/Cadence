import SwiftData
import Foundation

// Deep planner persistence (deep-planner-plan.md §3, §5). A ProjectPlan is the
// thin whole-horizon skeleton produced by /v1/plan/skeleton; its WorkUnits are
// the ordered work with objectives, hour estimates, and spacing constraints.
// Weekly placement (increment 2) will link generated Events back via these ids.
//
// NOTE: registered in SharedModelContainer.schema, so BOTH the app and the
// widget target must compile this file (target membership) — the widget never
// reads plans, but it opens the same store and needs the schema to match.

enum PlanGoalType: String, Codable {
    // Shared model enum — append cases only, never reorder.
    case study, project
}

enum PlanArchetype: String, Codable {
    // milestone = complete once, in order; repetition = revisit at growing gaps.
    case milestone, repetition
}

@Model
final class ProjectPlan {
    var id: UUID
    var title: String
    var goalType: PlanGoalType
    var deadline: Date?          // nil for open-ended goals
    var createdAt: Date
    // Cushion snapshot from the last skeleton/rebudget, in minutes.
    var neededMinutes: Int
    var availableMinutes: Int

    @Relationship(deleteRule: .cascade, inverse: \WorkUnit.plan)
    var workUnits: [WorkUnit]

    init(
        title: String,
        goalType: PlanGoalType,
        deadline: Date?,
        neededMinutes: Int,
        availableMinutes: Int
    ) {
        self.id = UUID()
        self.title = title
        self.goalType = goalType
        self.deadline = deadline
        self.createdAt = .now
        self.neededMinutes = neededMinutes
        self.availableMinutes = availableMinutes
        self.workUnits = []
    }

    var cushionMinutes: Int { availableMinutes - neededMinutes }
    /// Units in the skeleton's stated order.
    var orderedUnits: [WorkUnit] { workUnits.sorted { $0.order < $1.order } }
}

@Model
final class WorkUnit {
    var id: UUID
    /// The skeleton's own token ("W1") — how afterUnit/repeatOf reference units
    /// within this plan. Distinct from the SwiftData `id`.
    var unitKey: String
    var title: String
    var objective: String
    var estimatedMinutes: Int
    var archetype: PlanArchetype
    var order: Int

    // Spacing/ordering constraints from the skeleton; reference other unitKeys.
    var afterUnit: String?
    var repeatOf: String?
    var minGapDays: Int?
    var notLastNDaysBeforeDeadline: Int?

    @Relationship var plan: ProjectPlan?

    init(
        unitKey: String,
        title: String,
        objective: String,
        estimatedMinutes: Int,
        archetype: PlanArchetype,
        order: Int,
        afterUnit: String? = nil,
        repeatOf: String? = nil,
        minGapDays: Int? = nil,
        notLastNDaysBeforeDeadline: Int? = nil
    ) {
        self.id = UUID()
        self.unitKey = unitKey
        self.title = title
        self.objective = objective
        self.estimatedMinutes = estimatedMinutes
        self.archetype = archetype
        self.order = order
        self.afterUnit = afterUnit
        self.repeatOf = repeatOf
        self.minGapDays = minGapDays
        self.notLastNDaysBeforeDeadline = notLastNDaysBeforeDeadline
    }
}
