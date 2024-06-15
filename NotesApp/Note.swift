//
//  Note.swift
//  NotesApp
//
//  Created by Khan, Owais on 6/9/24.
//

import Foundation
import SwiftData

@Model

final class Note: Identifiable{
    var id = UUID()
    var title: String
    var content: String
    var createdAt: Date
    
    init(id: UUID = UUID(), title: String, description: String, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.content = description
        self.createdAt = createdAt
    }
}

extension Note{
    static var emptyList: [Note]{[]}
    static var mockData: [Note]{
        [
            Note(title: "Groccery List", description: "Milk, egg, Strawberries, Oil", createdAt: Date().addingTimeInterval(-100000)),
            Note(title: "Groccery List", description: "Milk, egg, Strawberries, Oil", createdAt: Date().addingTimeInterval(-200000)),
            Note(title: "Groccery List", description: "Milk, egg, Strawberries, Oil", createdAt: Date().addingTimeInterval(-300000)),
            Note(title: "Groccery List", description: "Milk, egg, Strawberries, Oil", createdAt: Date().addingTimeInterval(-400000)),
            Note(title: "Groccery List", description: "Milk, egg, Strawberries, Oil", createdAt: Date().addingTimeInterval(-500000))
        ]
    }
}
