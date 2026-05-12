//
//  Item.swift
//  GatherTab
//
//  Created by Nohyunsoo on 5/12/26.
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
