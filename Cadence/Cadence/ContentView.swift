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
        // All five screens stay mounted and crossfade by opacity (state/scroll
        // preserved like TabView) — the native bottom TabView can't animate its
        // content swap, so we drive it ourselves with a custom bar below. The
        // bar is a real VStack sibling, so it reserves its own space and content
        // never underlaps it (no per-view bottom padding needed).
        VStack(spacing: 0) {
            ZStack {
                tabScreen(.today)    { TodayView() }
                tabScreen(.schedule) { ScheduleView() }
                tabScreen(.habits)   { HabitsView() }
                tabScreen(.overview) { OverviewView() }
                tabScreen(.settings) { SettingsView() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.22), value: selectedTab)

            tabBar
        }
        .tint(theme.accent)
        .environment(\.theme, theme)
        // `.system` follows the device (nil); forced modes pin the scheme so
        // system chrome (keyboards, sheets) matches the surface set.
        .preferredColorScheme(themeMode == .system ? nil
                              : (themeMode == .dark ? .dark : .light))
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

    // MARK: - Tabs

    /// One tab's screen, kept mounted and crossfaded by opacity; hidden screens
    /// drop hit-testing so only the visible one receives touches.
    @ViewBuilder
    private func tabScreen<Content: View>(_ tab: Tab, @ViewBuilder _ content: () -> Content) -> some View {
        NavigationStack { content() }
            .opacity(selectedTab == tab ? 1 : 0)
            .allowsHitTesting(selectedTab == tab)
    }

    private var tabItems: [(tab: Tab, icon: String, label: String)] {
        [(.today,    "clock.fill",          "Today"),
         (.schedule, "calendar",            "Schedule"),
         (.habits,   "bolt.heart.fill",     "Habits"),
         (.overview, "chart.xyaxis.line",   "Overview"),
         (.settings, "slider.horizontal.3", "Settings")]
    }

    /// Custom bottom bar matching the old native styling: accent for the selected
    /// item, `text2` for the rest, a thin material background that fills into the
    /// home indicator, and a hairline top divider.
    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(tabItems, id: \.tab) { item in
                let selected = selectedTab == item.tab
                Button { selectedTab = item.tab } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.icon)
                            .font(.system(size: 18))
                            .frame(height: 22)
                        Text(item.label)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(selected ? theme.accent : theme.text2)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 2)
        .background(.thinMaterial, ignoresSafeAreaEdges: .bottom)
        .overlay(alignment: .top) {
            Rectangle().fill(theme.divider).frame(height: 0.5)
        }
        .animation(.easeInOut(duration: 0.22), value: selectedTab)
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
