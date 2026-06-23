import SwiftUI

struct ContentView: View {
    @AppStorage("accentColorHex") private var accentColorHex = "#E8784D"

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
    }
}

#Preview {
    ContentView()
        .modelContainer(
            for: [Event.self, Category.self, Meal.self, UserPreferences.self, Habit.self],
            inMemory: true
        )
}
