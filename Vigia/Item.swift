//
//  Item.swift
//  Vigia
//
//  Created by Weslley Oliveira on 04/10/26.
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
