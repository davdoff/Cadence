import SwiftUI
import SwiftData

struct ContentView: View {
    private enum Tab: Hashable {
        case today, schedule, habits, overview, settings
    }

    @AppStorage("accentColorHex") private var accentColorHex = "#E8784D"
    @AppStorage("themeMode") private var themeModeRaw = ThemeMode.system.rawValue
    @AppStorage("lastMealPassDay") private var lastMealPassDay = ""

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.modelContext) private var context
    @Query(sort: \Event.startTime) private var allEvents: [Event]
    @Query private var allMeals: [Meal]
    @Query private var prefsResults: [UserPreferences]
    @Query private var categories: [Category]

    @State private var selectedTab: Tab = .today

    private var themeMode: ThemeMode { ThemeMode(rawValue: themeModeRaw) ?? .system }

    /// Whether to render the dark surface set: forced modes decide directly;
    /// `.system` follows the device color scheme.
    private var useDarkSurface: Bool {
        switch themeMode {
        case .system: return systemScheme == .dark
        case .light:  return false
        case .dark:   return true
        }
    }

    // The one place accent + surface become a Theme; every view below reads
    // @Environment(\.theme) instead of re-deriving colors from AppStorage.
    private var theme: Theme {
        Theme(accentHex: accentColorHex, surface: useDarkSurface ? .dark : .light)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { TodayView() }
                .tabItem { Label("Today",    systemImage: "clock.fill")           }
                .tag(Tab.today)

            NavigationStack { ScheduleView() }
                .tabItem { Label("Schedule", systemImage: "calendar")             }
                .tag(Tab.schedule)

            NavigationStack { HabitsView() }
                .tabItem { Label("Habits",   systemImage: "bolt.heart.fill")      }
                .tag(Tab.habits)

            NavigationStack { OverviewView() }
                .tabItem { Label("Overview", systemImage: "chart.xyaxis.line")    }
                .tag(Tab.overview)

            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3")  }
                .tag(Tab.settings)
        }
        .tint(theme.accent)
        .environment(\.theme, theme)
        // `.system` follows the device (nil); forced modes pin the scheme so
        // system chrome (keyboards, sheets) matches the surface set.
        .preferredColorScheme(themeMode == .system ? nil
                              : (themeMode == .dark ? .dark : .light))
        // Tab-bar chrome (§4): re-applied whenever accent or surface changes.
        .onAppear { theme.configureTabBarAppearance() }
        .onChange(of: accentColorHex) { _, _ in theme.configureTabBarAppearance() }
        .onChange(of: useDarkSurface) { _, _ in theme.configureTabBarAppearance() }
        .task {
            await runDailyMealPassIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await runDailyMealPassIfNeeded() }
            }
        }
        .onOpenURL { url in
            guard url.scheme == "cadence" else { return }
            switch url.host() {
            case "today":              selectedTab = .today
            case "schedule", "meals":  selectedTab = .schedule
            case "habits":             selectedTab = .habits
            default:                   break
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
        let coordinator = MealPlanningCoordinator(mealCategory: mealCategory)
        let result = coordinator.runDailyPass(
            existingEvents: allEvents,
            allMeals: allMeals,
            preferences: p
        )
        for event in result.eventsToDelete { context.delete(event) }
        for event in result.newEvents { context.insert(event) }
        try? context.save()
        WidgetSync.refresh()
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
