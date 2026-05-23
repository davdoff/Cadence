import SwiftUI
import SwiftData

@main
struct SmartSchedulerApp: App {
    let container: ModelContainer = {
        let schema = Schema([
            Event.self,
            Category.self,
            Meal.self,
            UserPreferences.self
        ])
        return try! ModelContainer(for: schema)
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
