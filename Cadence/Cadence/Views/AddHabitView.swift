import SwiftUI
import SwiftData

struct AddHabitView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var categories: [Category]

    @State private var name = ""
    @State private var type: HabitType = .good
    @State private var selectedSymbol = "star.fill"
    @State private var selectedColor  = "#E8784D"
    @State private var dailyGoal  = 1
    @State private var weeklyGoal = 0
    @State private var correlatedCategoryName: String? = nil

    private var symbols: [String] { type == .good ? Habit.goodSymbols : Habit.badSymbols }
    private var accent:  Color    { Color(hex: selectedColor) }

    var body: some View {
        NavigationStack {
            ZStack {
                theme.backgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        previewCard
                        symbolPickerCard
                        colorPickerCard
                        detailsCard
                        goalsCard
                        categoryCard
                    }
                    .padding()
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("New Habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundColor(accent)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .foregroundColor(name.trimmingCharacters(in: .whitespaces).isEmpty ? .secondary : accent)
                }
            }
        }
    }

    // MARK: - Preview card

    private var previewCard: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(accent.opacity(0.15))
                    .frame(width: 56, height: 56)
                Image(systemName: selectedSymbol)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(accent)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(name.isEmpty ? "Habit name" : name)
                    .font(.headline)
                    .foregroundColor(name.isEmpty ? .secondary : .primary)
                HStack(spacing: 6) {
                    Image(systemName: type == .good ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                        .font(.caption)
                        .foregroundColor(type == .good ? accent : .red.opacity(0.7))
                    Text(type == .good ? "Good habit" : "Bad habit")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Text("0")
                .font(.title2.weight(.bold))
                .foregroundColor(accent)
        }
        .padding(16)
        .background(theme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: accent.opacity(0.12), radius: 8, y: 3)
    }

    // MARK: - Symbol picker

    private var symbolPickerCard: some View {
        cardContainer(title: "Icon") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                ForEach(symbols, id: \.self) { sym in
                    Button {
                        withAnimation(.spring(duration: 0.2)) { selectedSymbol = sym }
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(selectedSymbol == sym ? accent : accent.opacity(0.1))
                            Image(systemName: sym)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(selectedSymbol == sym ? .white : accent)
                        }
                        .frame(height: 48)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Color picker

    private var colorPickerCard: some View {
        cardContainer(title: "Colour") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 10) {
                ForEach(Habit.presetColors, id: \.self) { hex in
                    Button {
                        withAnimation(.spring(duration: 0.2)) { selectedColor = hex }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 36, height: 36)
                            if selectedColor == hex {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Details

    private var detailsCard: some View {
        cardContainer(title: "Details") {
            VStack(spacing: 0) {
                TextField("Habit name", text: $name)
                    .padding(.vertical, 10)

                Divider().overlay(theme.deep)

                Picker("Type", selection: $type) {
                    Label("Build it", systemImage: "arrow.up.circle.fill").tag(HabitType.good)
                    Label("Break it", systemImage: "arrow.down.circle.fill").tag(HabitType.bad)
                }
                .pickerStyle(.segmented)
                .padding(.vertical, 10)
                .onChange(of: type) { _, newType in
                    selectedSymbol = newType == .good ? Habit.goodSymbols[0] : Habit.badSymbols[0]
                    selectedColor  = newType == .good ? "#E8784D" : "#E05252"
                }
            }
        }
    }

    // MARK: - Goals (good habits only)

    @ViewBuilder
    private var goalsCard: some View {
        if type == .good {
            cardContainer(title: "Goals") {
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Daily goal")
                                .font(.subheadline)
                            Text(dailyGoal == 0 ? "Track freely" : "\(dailyGoal)× per day")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Stepper("", value: $dailyGoal, in: 0...20)
                            .labelsHidden()
                    }
                    .padding(.vertical, 10)

                    Divider().overlay(theme.deep)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Weekly goal")
                                .font(.subheadline)
                            Text(weeklyGoal == 0 ? "No weekly target" : "\(weeklyGoal)× per week")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Stepper("", value: $weeklyGoal, in: 0...100)
                            .labelsHidden()
                    }
                    .padding(.vertical, 10)
                }
            }
        }
    }

    // MARK: - Category link

    private var categoryCard: some View {
        cardContainer(title: "Auto-track from events") {
            VStack(spacing: 0) {
                Picker("Linked category", selection: $correlatedCategoryName) {
                    Text("None").tag(nil as String?)
                    ForEach(categories) { cat in
                        Text(cat.name).tag(Optional(cat.name))
                    }
                }
                .pickerStyle(.menu)
                .padding(.vertical, 8)

                Text("When you complete an event in this category, the habit count auto-increments.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 8)
            }
        }
    }

    // MARK: - Card container helper

    private func cardContainer<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .padding(.leading, 2)
            content()
                .padding()
                .cardStyle()
        }
    }

    // MARK: - Save

    private func save() {
        context.insert(Habit(
            name: name.trimmingCharacters(in: .whitespaces),
            type: type,
            correlatedCategoryName: correlatedCategoryName,
            symbolName: selectedSymbol,
            colorHex: selectedColor,
            dailyGoal: dailyGoal,
            weeklyGoal: weeklyGoal
        ))
        try? context.save()
        WidgetSync.refresh()
        dismiss()
    }
}
