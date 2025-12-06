//
//  Item.swift
//  PocketMesh
//
//  Created by Nate Chung on 12/5/25.
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
