import SwiftUI
import SwiftData

struct AddHabitView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var categories: [Category]

    /// When non-nil the sheet edits this habit in place instead of creating one.
    private let editingHabit: Habit?

    @State private var name: String
    @State private var type: HabitType
    @State private var selectedSymbol: String
    @State private var selectedTileID: String
    @State private var dailyGoal:  Int
    @State private var weeklyGoal: Int
    @State private var correlatedCategoryName: String?

    init(editingHabit: Habit? = nil) {
        self.editingHabit = editingHabit
        _name          = State(initialValue: editingHabit?.name ?? "")
        _type          = State(initialValue: editingHabit?.type ?? .good)
        _selectedSymbol = State(initialValue: editingHabit?.symbolName ?? "star.fill")
        _selectedTileID = State(initialValue: editingHabit?.tileColorID ?? HabitTileColor.defaultID)
        _dailyGoal     = State(initialValue: editingHabit?.dailyGoal ?? 1)
        _weeklyGoal    = State(initialValue: editingHabit?.weeklyGoal ?? 0)
        _correlatedCategoryName = State(initialValue: editingHabit?.correlatedCategoryName)
    }

    private var isEditing: Bool { editingHabit != nil }
    private var symbols: [String] { type == .good ? Habit.goodSymbols : Habit.badSymbols }
    /// Live tile tokens for the chosen color, resolved for the active surface.
    private var tile:   HabitTileColor.Tokens { HabitTileColor.by(id: selectedTileID).tokens(dark: theme.isDark) }
    private var accent: Color { tile.icon }

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
            .navigationTitle(isEditing ? "Edit Habit" : "New Habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundColor(accent)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") { save() }
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
                    .fill(tile.tileGradient)
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
            // Driven by the extensible tile catalog, not a fixed hex list —
            // any tiles added to `HabitTileColor.all` show up automatically.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 12) {
                ForEach(HabitTileColor.all) { option in
                    let tokens = option.tokens(dark: theme.isDark)
                    let isSelected = selectedTileID == option.id
                    Button {
                        withAnimation(.spring(duration: 0.2)) { selectedTileID = option.id }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(tokens.buttonGradient)
                                .frame(width: 40, height: 40)
                                .shadow(color: tokens.solid.opacity(isSelected ? 0.5 : 0), radius: 5)
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 14)
                    .tapToFocus()

                Divider().overlay(theme.deep)

                Picker("Type", selection: $type) {
                    Label("Build it", systemImage: "arrow.up.circle.fill").tag(HabitType.good)
                    Label("Break it", systemImage: "arrow.down.circle.fill").tag(HabitType.bad)
                }
                .pickerStyle(.segmented)
                .padding(.vertical, 10)
                .onChange(of: type) { _, newType in
                    selectedSymbol = newType == .good ? Habit.goodSymbols[0] : Habit.badSymbols[0]
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
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        // Mirror the tile's solid color into colorHex so the widget (which reads
        // colorHex) stays visually in sync until Phase 6.
        let solidHex = HabitTileColor.by(id: selectedTileID).solidHex

        if let habit = editingHabit {
            habit.name = trimmed
            habit.type = type
            habit.correlatedCategoryName = correlatedCategoryName
            habit.symbolName = selectedSymbol
            habit.colorHex = solidHex
            habit.tileColorID = selectedTileID
            habit.dailyGoal = type == .good ? max(dailyGoal, 0) : 0
            habit.weeklyGoal = weeklyGoal
        } else {
            context.insert(Habit(
                name: trimmed,
                type: type,
                correlatedCategoryName: correlatedCategoryName,
                symbolName: selectedSymbol,
                colorHex: solidHex,
                tileColorID: selectedTileID,
                dailyGoal: dailyGoal,
                weeklyGoal: weeklyGoal
            ))
        }
        try? context.save()
        WidgetSync.refresh()
        dismiss()
    }
}
