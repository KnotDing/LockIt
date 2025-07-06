//
//  Item.swift
//  LockIt
//
//  Created by Knot Ding on 2025/7/6.
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
