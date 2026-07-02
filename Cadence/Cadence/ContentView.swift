import SwiftUI
import SwiftData

struct ContentView: View {
    @AppStorage("accentColorHex") private var accentColorHex = "#E8784D"
    @AppStorage("lastMealPassDay") private var lastMealPassDay = ""

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
    @Query(sort: \Event.startTime) private var allEvents: [Event]
    @Query private var allMeals: [Meal]
    @Query private var prefsResults: [UserPreferences]
    @Query private var categories: [Category]

    var body: some View {
        TabView {
            NavigationStack { TodayView() }
                .tabItem { Label("Today",    systemImage: "clock.fill")           }

            NavigationStack { ScheduleView() }
                .tabItem { Label("Schedule", systemImage: "calendar")             }

            NavigationStack { HabitsView() }
                .tabItem { Label("Habits",   systemImage: "bolt.heart.fill")      }

            NavigationStack { OverviewView() }
                .tabItem { Label("Overview", systemImage: "chart.xyaxis.line")    }

            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3")  }
        }
        .tint(Color(hex: accentColorHex))
        .preferredColorScheme(.light)
        .task {
            await runDailyMealPassIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await runDailyMealPassIfNeeded() }
            }
        }
    }

    // MARK: - Day-start meal pass

    /// Runs the meal scheduling pass once per calendar day, so meals are planned
    /// at day start instead of a week ahead.
    @MainActor
    private func runDailyMealPassIfNeeded() async {
        let todayKey = Date().formatted(.iso8601.year().month().day())
        guard todayKey != lastMealPassDay else { return }
        guard let p = prefsResults.first else { return }

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
        for event in result.eventsToDelete { context.delete(event) }
        for event in result.newEvents { context.insert(event) }
        if let meal = result.newMeal {
            context.insert(meal)
            p.knownMealIDs.append(meal.id)
        }
        try? context.save()
        lastMealPassDay = todayKey
    }
}

#Preview {
    ContentView()
        .modelContainer(
            for: [Event.self, Category.self, Meal.self, UserPreferences.self, Habit.self],
            inMemory: true
        )
}
