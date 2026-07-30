import SwiftUI
import SwiftData

/// Intake for a new deep plan. Increment 1 is a single-shot form; the multiturn
/// clarify conversation (`/v1/plan/intake`) replaces this submit path in
/// increment 3 (see `deep-planner-plan.md` §4, §7).
///
/// The form fields map to the `/v1/plan/skeleton` request. `AIService` returns a
/// plain `PlanSkeletonResult`; this view maps it onto SwiftData (CLAUDE.md rule
/// 3 — AIService never touches the context).
struct DeepPlanIntakeView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    enum GoalType: String, CaseIterable, Identifiable {
        case study = "Study", project = "Project"
        var id: String { rawValue }
        var wire: String { self == .study ? "study" : "project" }
    }

    @State private var goal = ""
    @State private var goalType: GoalType = .study
    @State private var hasDeadline = true
    @State private var deadline = Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now
    @State private var weeklyHours = 6

    @State private var isGenerating = false
    @State private var errorMessage: String?

    private var canSubmit: Bool {
        !goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isGenerating
    }

    var body: some View {
        NavigationStack {
            ZStack {
                theme.backgroundGradient.ignoresSafeArea()
                Form {
                    Section("What's the goal?") {
                        TextField("e.g. Pass the Signals & Systems exam", text: $goal, axis: .vertical)
                            .lineLimit(2...5)
                    }

                    Section("Type") {
                        Picker("Type", selection: $goalType) {
                            ForEach(GoalType.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }

                    Section("Deadline") {
                        Toggle("Has a deadline", isOn: $hasDeadline)
                        if hasDeadline {
                            DatePicker("Target date", selection: $deadline, in: Date()..., displayedComponents: .date)
                        }
                    }

                    Section("Time you can give it") {
                        Stepper("\(weeklyHours) hours per week", value: $weeklyHours, in: 1...40)
                    }

                    Section {
                        Button(action: generatePlan) {
                            Group {
                                if isGenerating {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("Generate plan").font(.subheadline.weight(.semibold))
                                }
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(canSubmit ? AnyShapeStyle(theme.accentGradient)
                                                  : AnyShapeStyle(theme.light))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(!canSubmit)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    } footer: {
                        if let errorMessage {
                            Text(errorMessage).foregroundColor(.red)
                        } else {
                            Text("The planner drafts a thin whole-horizon skeleton — you'll plan each week from it as you go.")
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("New plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func generatePlan() {
        guard canSubmit else { return }
        errorMessage = nil
        isGenerating = true
        let trimmedGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        let due = hasDeadline ? deadline : nil

        Task {
            do {
                let result = try await AIService().planSkeleton(
                    goal: trimmedGoal,
                    goalType: goalType.wire,
                    deadline: due,
                    weeklyHours: weeklyHours,
                    constraints: ""
                )
                persist(result)
                dismiss()
            } catch {
                errorMessage = (error as? AIServiceError)?.errorDescription
                    ?? "Couldn't build the plan. Try again."
                isGenerating = false
            }
        }
    }

    /// Map the server's plain result onto SwiftData. The view owns persistence;
    /// AIService stays detached (CLAUDE.md rule 3).
    private func persist(_ result: PlanSkeletonResult) {
        let plan = ProjectPlan(
            title: result.title,
            goalType: result.goalType == "project" ? .project : .study,
            deadline: result.deadline,
            neededMinutes: result.capacity.neededMinutes,
            availableMinutes: result.capacity.availableMinutes
        )
        context.insert(plan)
        for (index, unit) in result.workUnits.enumerated() {
            let workUnit = WorkUnit(
                unitKey: unit.id,
                title: unit.title,
                objective: unit.objective,
                estimatedMinutes: unit.estimatedMinutes,
                archetype: unit.archetype == "repetition" ? .repetition : .milestone,
                order: index,
                afterUnit: unit.afterUnit,
                repeatOf: unit.repeatOf,
                minGapDays: unit.minGapDays,
                notLastNDaysBeforeDeadline: unit.notLastNDaysBeforeDeadline
            )
            workUnit.plan = plan
            context.insert(workUnit)
        }
        try? context.save()
    }
}
