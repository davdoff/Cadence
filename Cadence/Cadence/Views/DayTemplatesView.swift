import SwiftUI
import SwiftData

/// Settings › Scheduling › Day Templates: the template library. Day templates
/// are edited in `DayTemplateEditorView`; week layouts (weekday → day template)
/// are usually saved from the "Plan a period…" sheet and can be tweaked or
/// deleted here. Applying templates lives in that sheet, not here.
struct DayTemplatesView: View {
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var context
    @Query(sort: \DayTemplate.name) private var templates: [DayTemplate]
    @Query(sort: \WeekTemplate.name) private var weekTemplates: [WeekTemplate]

    var body: some View {
        ZStack {
            theme.backgroundGradient.ignoresSafeArea()

            List {
                Section {
                    ForEach(templates) { template in
                        NavigationLink {
                            DayTemplateEditorView(template: template)
                        } label: {
                            DayTemplateRow(template: template)
                        }
                        .listRowBackground(theme.cardSurface)
                    }
                    .onDelete { offsets in
                        for i in offsets { context.delete(templates[i]) }
                        try? context.save()
                    }
                } header: {
                    Text("Day templates")
                } footer: {
                    if templates.isEmpty {
                        Text("Save a typical day — work, sport, study — and stamp it onto any date from Ask AI › Plan a period.")
                    }
                }

                if !weekTemplates.isEmpty {
                    Section("Week layouts") {
                        ForEach(weekTemplates) { week in
                            NavigationLink {
                                WeekTemplateEditorView(week: week)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(week.name).font(.subheadline.weight(.medium))
                                    Text(summary(of: week))
                                        .font(.caption).foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                .padding(.vertical, 2)
                            }
                            .listRowBackground(theme.cardSurface)
                        }
                        .onDelete { offsets in
                            for i in offsets { context.delete(weekTemplates[i]) }
                            try? context.save()
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Day Templates")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(theme.background, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    DayTemplateEditorView(template: nil)
                } label: {
                    Image(systemName: "plus").foregroundColor(theme.accent)
                }
            }
        }
    }

    /// "Mon Work day · Sat Sporty day" — weekdays in Monday-first order.
    private func summary(of week: WeekTemplate) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols
        let parts = WeekTemplateEditorView.mondayFirst.compactMap { weekday -> String? in
            guard let id = week.templateID(forWeekday: weekday),
                  let template = templates.first(where: { $0.id == id }) else { return nil }
            return "\(symbols[weekday - 1]) \(template.name)"
        }
        return parts.isEmpty ? "No days assigned" : parts.joined(separator: " · ")
    }
}

private struct DayTemplateRow: View {
    @Environment(\.theme) private var theme
    let template: DayTemplate

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: template.symbolName ?? "square.grid.2x2")
                .foregroundColor(theme.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(template.name).font(.subheadline.weight(.medium))
                Text("\(template.blocks.count) block\(template.blocks.count == 1 ? "" : "s")")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Week layout editor

/// One picker per weekday. Edits write straight to the model (a week layout is
/// tiny and has no invalid intermediate state).
struct WeekTemplateEditorView: View {
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var context
    @Query(sort: \DayTemplate.name) private var templates: [DayTemplate]
    @Bindable var week: WeekTemplate

    /// Calendar weekdays (1 = Sunday) in Monday-first display order.
    static let mondayFirst = [2, 3, 4, 5, 6, 7, 1]

    var body: some View {
        ZStack {
            theme.backgroundGradient.ignoresSafeArea()
            Form {
                Section("Name") {
                    TextField("Week layout name", text: $week.name)
                }
                Section("Days") {
                    ForEach(Self.mondayFirst, id: \.self) { weekday in
                        Picker(Calendar.current.weekdaySymbols[weekday - 1], selection: binding(for: weekday)) {
                            Text("None").tag(UUID?.none)
                            ForEach(templates) { Text($0.name).tag(UUID?.some($0.id)) }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(week.name.isEmpty ? "Week layout" : week.name)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { try? context.save() }
    }

    private func binding(for weekday: Int) -> Binding<UUID?> {
        Binding(
            get: { week.templateID(forWeekday: weekday) },
            set: { newValue in
                var assignments = week.assignments.filter { $0.weekday != weekday }
                if let id = newValue { assignments.append(WeekdayAssignment(weekday: weekday, templateID: id)) }
                week.assignments = assignments
            }
        )
    }
}
