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
    let modelContainer: ModelContainer
    
    init(){
        do{
            modelContainer = try ModelContainer(for: Note.self)
        }catch{
            fatalError("COuld not initialize ModelContainer")
        }
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
