import SwiftUI
import SwiftData

/// Only here to give a second screen its own scene; every other scene is SwiftUI's.
final class ScribeAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        if connectingSceneSession.role == .windowExternalDisplayNonInteractive { configuration.delegateClass = ExternalDisplaySceneDelegate.self }
        return configuration
    }
}

@main
struct SwiftScribeApp: App {
    @UIApplicationDelegateAdaptor(ScribeAppDelegate.self) private var delegate

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
        }
        .background(Color.paper.ignoresSafeArea())
        .environment(app)
        .environment(app.library)
        .environment(app.activity)
        .modelContainer(app.container)
        .task {
            #if DEBUG
            if LaunchOptions.arguments.contains("-framePacing") { FramePacingWindow.install() }
            #endif
            await app.start()
            await WidgetBridge.update(app)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                app.flushOpenDocuments()
                app.activity.flush()
                Task { await WidgetBridge.update(app) }
            }
        }
    }
}
