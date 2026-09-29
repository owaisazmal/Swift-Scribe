import SwiftUI
import SwiftData

@main
struct SwiftScribeApp: App {
    var body: some Scene {
        WindowGroup {
            if LaunchOptions.usesV2 {
                ScribeRoot()
            } else {
                LegacyRoot()
            }
        }
    }
}

struct ScribeRoot: View {
    @State private var app = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            LibraryRootView()
                .opacity(app.phase == .ready ? 1 : 0)
            if app.phase == .migrating {
                VStack(spacing: Space.x4) {
                    ProgressView().controlSize(.large)
                    Text("Moving your notebooks to the new format…").font(.displayText(19, relativeTo: .title3))
                    Text("Your originals are kept as a backup.").foregroundStyle(Color.inkSecondary)
                }
                .foregroundStyle(Color.ink)
                .accessibilityElement(children: .combine)
            }
        }
        .background(Color.paper.ignoresSafeArea())
        .environment(app)
        .environment(app.library)
        .modelContainer(app.container)
        .task { await app.start() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { app.flushOpenDocuments() }
        }
    }
}

struct LegacyRoot: View {
    private static let container: ModelContainer = {
        do {
            let configuration = ModelConfiguration("SwiftScribe", schema: Schema([Notebook.self, Folder.self]))
            return try ModelContainer(for: Notebook.self, Folder.self, configurations: configuration)
        } catch {
            fatalError("Could not open the notebook library: \(error)")
        }
    }()

    var body: some View {
        LibraryView().modelContainer(Self.container)
    }
}
