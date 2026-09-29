import SwiftUI
import SwiftData

@main
struct SwiftScribeApp: App {
    var body: some Scene {
        WindowGroup {
            ScribeRoot()
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
        .task {
            #if DEBUG
            if LaunchOptions.arguments.contains("-framePacing") { FramePacingWindow.install() }
            #endif
            await app.start()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { app.flushOpenDocuments() }
        }
        .alert("Some notebooks weren't moved", isPresented: $app.showsMigrationProblem) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\(app.migrationProblem ?? "") Your original notebooks are untouched, and Swift Scribe will try again the next time it opens.")
        }
    }
}
