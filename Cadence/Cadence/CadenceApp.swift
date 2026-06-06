import SwiftUI
import SwiftData

@main
struct CadenceApp: App {
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
                .task { await seedIfNeeded() }
        }
        .modelContainer(container)
    }

    @MainActor
    private func seedIfNeeded() async {
        let context = container.mainContext
        let categoryCount = (try? context.fetchCount(FetchDescriptor<Category>())) ?? 0
        guard categoryCount == 0 else { return }

        let defaults: [(String, String)] = [
            ("Work",     "#4A90E2"),
            ("Study",    "#7B68EE"),
            ("Health",   "#5CB85C"),
            ("Meal",     "#F0AD4E"),
            ("Personal", "#9B59B6")
        ]
        for (name, hex) in defaults {
            context.insert(Category(name: name, colorHex: hex))
        }

        context.insert(UserPreferences())
        try? context.save()
    }
}
