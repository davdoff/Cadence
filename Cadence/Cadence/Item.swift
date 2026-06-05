//
//  Item.swift
//  Cadence
//
//  Created by David Botosineanu on 06.06.2026.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
