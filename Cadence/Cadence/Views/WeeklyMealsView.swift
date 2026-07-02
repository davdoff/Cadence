import SwiftUI
import SwiftData

struct WeeklyMealsView: View {
    @Query(sort: \Event.startTime) private var allEvents: [Event]
    @Query private var allMeals: [Meal]
    @Query private var prefsResults: [UserPreferences]
    @Query private var categories: [Category]
    @Environment(\.modelContext) private var context
    @AppStorage("accentColorHex") private var accentColorHex = "#E8784D"

    @State private var isRunningPass = false

    private var prefs: UserPreferences? { prefsResults.first }

    private var weekDates: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today) // 1=Sun … 7=Sat
        let daysSinceMonday = (weekday + 5) % 7           // Sun→6, Mon→0, Tue→1 …
        let monday = cal.date(byAdding: .day, value: -daysSinceMonday, to: today)!
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: monday) }
    }

    private var hasPrefsSet: Bool {
        guard let p = prefs else { return false }
        return p.breakfastEnabled || !p.knownMealIDs.isEmpty
    }

    var body: some View {
        ZStack {
            Color.cadenceCream.ignoresSafeArea()

            if !hasPrefsSet {
                emptyState
            } else {
                weekList
            }
        }
        .navigationTitle("Meals This Week")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.cadenceCream, for: .navigationBar)
        .overlay(alignment: .top) {
            if isRunningPass {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(Color(hex: accentColorHex))
                    .frame(height: 2)
            }
        }
        .task {
            await runDailyPass()
        }
    }

    // MARK: - Week list

    private var weekList: some View {
        List {
            ForEach(weekDates, id: \.self) { date in
                dayCard(for: date)
                    .listRowBackground(Color.cadenceCream)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func dayCard(for date: Date) -> some View {
        let cal = Calendar.current
        let isPast = date < cal.startOfDay(for: Date())
        let isToday = cal.isDateInToday(date)
        let isFuture = !isPast && !isToday
        let events = mealEvents(for: date)
        let breakfast = events.first { $0.title == "Breakfast" }
        let dinner = events.first { $0.title != "Breakfast" }

        return HStack(alignment: .top, spacing: 14) {
            // Day label column
            VStack(spacing: 2) {
                Text(date.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.secondary)
                Text(date.formatted(.dateTime.day()))
                    .font(.subheadline.weight(isToday ? .bold : .regular))
                    .foregroundColor(isToday ? Color(hex: accentColorHex) : .primary)
            }
            .frame(width: 34)
            .padding(.top, 2)

            // Meal slots
            VStack(alignment: .leading, spacing: 10) {
                breakfastSlot(event: breakfast, isFuture: isFuture)
                dinnerSlot(event: dinner, isFuture: isFuture)
            }
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
        .opacity(isPast ? 0.55 : (isFuture ? 0.75 : 1))
    }

    // MARK: - Slot rows

    @ViewBuilder
    private func breakfastSlot(event: Event?, isFuture: Bool) -> some View {
        if let event {
            slotContent(
                icon: "sunrise.fill",
                title: event.title,
                time: event.startTime,
                isAIPick: false
            )
        } else if isFuture {
            emptySlot(icon: "sunrise.fill", label: "Planned on the day")
        } else {
            emptySlot(icon: "sunrise.fill", label: "Skipped")
        }
    }

    @ViewBuilder
    private func dinnerSlot(event: Event?, isFuture: Bool) -> some View {
        if let event {
            NavigationLink {
                EventDetailView(event: event)
            } label: {
                slotContent(
                    icon: "fork.knife",
                    title: event.title,
                    time: event.startTime,
                    isAIPick: isAIPick(event: event)
                )
            }
            .buttonStyle(.plain)
        } else if isFuture {
            emptySlot(icon: "fork.knife", label: "Planned on the day")
        } else {
            emptySlot(icon: "fork.knife", label: "No slot")
        }
    }

    private func slotContent(icon: String, title: String, time: Date, isAIPick: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(.cadenceOrangeLight)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.primary)

                    if isAIPick {
                        HStack(spacing: 3) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 7, weight: .bold))
                            Text("AI pick")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundColor(Color(hex: accentColorHex))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color(hex: accentColorHex).opacity(0.12))
                        .clipShape(Capsule())
                    }
                }

                Text(time, format: .dateTime.hour().minute())
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func emptySlot(icon: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.3))
                .frame(width: 16)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.5))
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.cadenceOrangeLight.opacity(0.15))
                    .frame(width: 90, height: 90)
                Image(systemName: "fork.knife")
                    .font(.system(size: 38))
                    .foregroundColor(.cadenceOrangeLight)
            }
            Text("No meal preferences set")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Set up your meal preferences to get started.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            NavigationLink {
                FoodPreferencesView()
            } label: {
                Text("Set Up Meals")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .background(Color.cadenceOrange)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func mealEvents(for date: Date) -> [Event] {
        let cal = Calendar.current
        return allEvents.filter {
            cal.isDate($0.startTime, inSameDayAs: date) &&
            $0.category?.name == "Meal" &&
            $0.source == .ai
        }
    }

    private func isAIPick(event: Event) -> Bool {
        allMeals.contains { $0.name == event.title && !$0.isUserDefined }
    }

    // MARK: - Daily pass

    @MainActor
    private func runDailyPass() async {
        guard let p = prefs else { return }
        isRunningPass = true
        defer { isRunningPass = false }

        let mealCategory = categories.first { $0.name == "Meal" }
        let coordinator = MealPlanningCoordinator(
            aiService: AIService(),
            mealCategory: mealCategory
        )
        let result = await coordinator.runDailyPass(
            existingEvents: allEvents,
            allMeals: allMeals,
            preferences: p
        )
        for event in result.eventsToDelete {
            context.delete(event)
        }
        for event in result.newEvents {
            context.insert(event)
        }
        if let meal = result.newMeal {
            context.insert(meal)
            p.knownMealIDs.append(meal.id)
        }
        try? context.save()
    }
}
