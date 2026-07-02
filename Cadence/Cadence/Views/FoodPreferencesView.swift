import SwiftUI
import SwiftData

struct FoodPreferencesView: View {
    @Query private var prefsResults: [UserPreferences]
    @Query private var allMeals: [Meal]
    @Query(sort: \Event.startTime) private var allEvents: [Event]
    @Query private var categories: [Category]
    @Environment(\.modelContext) private var context
    @AppStorage("accentColorHex") private var accentColorHex = "#E8784D"

    @State private var breakfastEnabled = true
    @State private var breakfastTime = Date()
    @State private var dinnerStart = Date()
    @State private var dinnerEnd = Date()
    @State private var newMealSuggestionEnabled = true
    @State private var mealGuidance = ""
    @State private var showingAddMeal = false

    private var prefs: UserPreferences? { prefsResults.first }

    private var knownMeals: [Meal] {
        guard let p = prefs else { return [] }
        let ids = Set(p.knownMealIDs)
        return allMeals.filter { ids.contains($0.id) }
    }

    private var isDinnerWindowValid: Bool { dinnerEnd > dinnerStart }

    var body: some View {
        ZStack {
            Color.cadenceCream.ignoresSafeArea()
            Form {
                breakfastSection
                dinnerSection
                mealsSection
                discoverySection
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Food")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.cadenceCream, for: .navigationBar)
        .onAppear(perform: loadPrefs)
        .onDisappear(perform: triggerDailyPass)
        .sheet(isPresented: $showingAddMeal) {
            AddMealView { name, prep in addMeal(name: name, prepTimeMinutes: prep) }
        }
    }

    // MARK: - Sections

    private var breakfastSection: some View {
        Section("Breakfast") {
            Toggle("Schedule breakfast", isOn: $breakfastEnabled)
                .tint(Color(hex: accentColorHex))
                .onChange(of: breakfastEnabled) { savePrefs() }

            if breakfastEnabled {
                HStack {
                    Text("Time")
                    Spacer()
                    DatePicker("", selection: $breakfastTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .onChange(of: breakfastTime) { savePrefs() }
                }

                Text("A 30-min breakfast block will be added to your schedule each morning. Days with a conflict nearby are skipped automatically.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var dinnerSection: some View {
        Section {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Start")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    DatePicker("", selection: $dinnerStart, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .onChange(of: dinnerStart) { savePrefs() }
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("End")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    DatePicker("", selection: $dinnerEnd, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .onChange(of: dinnerEnd) { savePrefs() }
                }
            }
            .padding(.vertical, 4)

            if !isDinnerWindowValid {
                Label("End time must be after start time.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        } header: {
            Text("Dinner Window")
        }
    }

    private var mealsSection: some View {
        Section {
            ForEach(knownMeals) { meal in
                mealRow(meal)
            }
            .onDelete(perform: deleteMeals)

            Button {
                showingAddMeal = true
            } label: {
                Label("Add meal", systemImage: "plus.circle.fill")
                    .foregroundColor(Color(hex: accentColorHex))
            }
        } header: {
            Text("My Meals")
        }
    }

    private var discoverySection: some View {
        Section("Meal Discovery") {
            Toggle("Suggest a new meal to try each week", isOn: $newMealSuggestionEnabled)
                .tint(Color(hex: accentColorHex))
                .onChange(of: newMealSuggestionEnabled) { savePrefs() }

            if newMealSuggestionEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Guidance")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    TextField("e.g. vegetarian, more chicken, rice dishes", text: $mealGuidance, axis: .vertical)
                        .font(.subheadline)
                        .onChange(of: mealGuidance) { savePrefs() }
                    Text("Tell the AI what to look for — dietary restrictions, favourite ingredients, cuisines.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)

                HStack {
                    Text("Last suggestion")
                        .foregroundColor(.secondary)
                    Spacer()
                    if let lastDate = prefs?.lastNewMealSuggestedDate {
                        Text(lastDate, format: .relative(presentation: .named))
                            .foregroundColor(.secondary)
                    } else {
                        Text("Not suggested yet")
                            .foregroundColor(.secondary)
                    }
                }
                .font(.subheadline)
            }
        }
    }

    // MARK: - Meal Row

    private func mealRow(_ meal: Meal) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(meal.name)
                    .font(.subheadline.weight(.medium))
                if !meal.isUserDefined {
                    HStack(spacing: 3) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 8, weight: .bold))
                        Text("AI pick")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(Color(hex: accentColorHex))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color(hex: accentColorHex).opacity(0.12))
                    .clipShape(Capsule())
                }
            }
            Spacer()
            Text("\(meal.prepTimeMinutes) min")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Actions

    private func addMeal(name: String, prepTimeMinutes: Int) {
        guard let p = prefs else { return }
        let meal = Meal(name: name, prepTimeMinutes: prepTimeMinutes, isUserDefined: true)
        context.insert(meal)
        p.knownMealIDs.append(meal.id)
        try? context.save()
    }

    private func deleteMeals(at offsets: IndexSet) {
        guard let p = prefs else { return }
        for index in offsets {
            p.knownMealIDs.removeAll { $0 == knownMeals[index].id }
        }
        try? context.save()
    }

    // MARK: - Persistence

    private func loadPrefs() {
        guard let p = prefs else { return }
        breakfastEnabled = p.breakfastEnabled
        newMealSuggestionEnabled = p.newMealSuggestionEnabled
        mealGuidance = p.mealGuidance

        let cal = Calendar.current
        var base = cal.dateComponents([.year, .month, .day], from: Date())

        base.hour = p.breakfastHour; base.minute = p.breakfastMinute
        breakfastTime = cal.date(from: base) ?? Date()

        base.hour = p.dinnerWindowStartHour; base.minute = p.dinnerWindowStartMinute
        dinnerStart = cal.date(from: base) ?? Date()

        base.hour = p.dinnerWindowEndHour; base.minute = p.dinnerWindowEndMinute
        dinnerEnd = cal.date(from: base) ?? Date()
    }

    private func savePrefs() {
        guard let p = prefs else { return }
        let cal = Calendar.current

        p.breakfastEnabled = breakfastEnabled
        p.newMealSuggestionEnabled = newMealSuggestionEnabled
        p.mealGuidance = mealGuidance
        p.breakfastHour = cal.component(.hour, from: breakfastTime)
        p.breakfastMinute = cal.component(.minute, from: breakfastTime)

        if isDinnerWindowValid {
            p.dinnerWindowStartHour = cal.component(.hour, from: dinnerStart)
            p.dinnerWindowStartMinute = cal.component(.minute, from: dinnerStart)
            p.dinnerWindowEndHour = cal.component(.hour, from: dinnerEnd)
            p.dinnerWindowEndMinute = cal.component(.minute, from: dinnerEnd)
        }

        try? context.save()
    }

    private func triggerDailyPass() {
        guard let p = prefs else { return }
        let mealCategory = categories.first { $0.name == "Meal" }
        let coordinator = MealPlanningCoordinator(
            aiService: AIService(),
            mealCategory: mealCategory
        )
        let events = allEvents
        let meals = allMeals
        let ctx = context
        Task { @MainActor in
            let result = await coordinator.runDailyPass(
                existingEvents: events,
                allMeals: meals,
                preferences: p
            )
            for event in result.eventsToDelete { ctx.delete(event) }
            for event in result.newEvents { ctx.insert(event) }
            if let meal = result.newMeal {
                ctx.insert(meal)
                p.knownMealIDs.append(meal.id)
            }
            try? ctx.save()
        }
    }
}
