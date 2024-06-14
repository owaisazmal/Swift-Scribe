//
//  NotesAppApp.swift
//  NotesApp
//
//  Created by Khan, Owais on 6/7/24.
//

import SwiftUI
import SwiftData

@main
struct NotesAppApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: Note.self)
    }
}
