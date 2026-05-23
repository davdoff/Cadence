import SwiftData
import Foundation

@Model
final class Category {
    var id: UUID
    var name: String
    var colorHex: String

    @Relationship(deleteRule: .nullify, inverse: \Event.category)
    var events: [Event]

    init(name: String, colorHex: String) {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
        self.events = []
    }
}
