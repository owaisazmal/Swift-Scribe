import SwiftUI
import SwiftData

@main
struct SwiftScribeApp: App {
    let container: ModelContainer

    init() {
        do {
            let configuration = ModelConfiguration("SwiftScribe", schema: Schema([Notebook.self, Folder.self]))
            container = try ModelContainer(for: Notebook.self, Folder.self, configurations: configuration)
        } catch {
            fatalError("Could not open the notebook library: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            LibraryView()
        }
        .modelContainer(container)
    }
}
