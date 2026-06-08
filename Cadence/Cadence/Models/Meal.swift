import SwiftData
import Foundation

@Model
final class Meal {
    var id: UUID
    var name: String
    var prepTimeMinutes: Int
    var isUserDefined: Bool
    var tags: [String]

    init(name: String, prepTimeMinutes: Int = 20, isUserDefined: Bool = true) {
        self.id = UUID()
        self.name = name
        self.prepTimeMinutes = prepTimeMinutes
        self.isUserDefined = isUserDefined
        self.tags = []
    }
}
