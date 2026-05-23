import SwiftData
import Foundation

@Model
final class Meal {
    var id: UUID
    var name: String
    var prepTimeMinutes: Int

    init(name: String, prepTimeMinutes: Int = 20) {
        self.id = UUID()
        self.name = name
        self.prepTimeMinutes = prepTimeMinutes
    }
}
