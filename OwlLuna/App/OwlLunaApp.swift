import SwiftUI
import SwiftData
import CoreSpotlight

/// Only here to give a second screen its own scene; every other scene is SwiftUI's.
final class OwlLunaAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        if connectingSceneSession.role == .windowExternalDisplayNonInteractive { configuration.delegateClass = ExternalDisplaySceneDelegate.self }
        return configuration
    }
}

@main
struct OwlLunaApp: App {
    @UIApplicationDelegateAdaptor(OwlLunaAppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            OwlLunaRoot()
        }
    }
}

struct OwlLunaRoot: View {
    @State private var app = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsLaunch = false
    /// The launch overlay has begun handing over, so the library is on its way in.
    @State private var libraryShown = false

    private var libraryOpacity: Double {
        if showsLaunch { return libraryShown ? 1 : 0 }
        return app.phase == .ready ? 1 : 0
    }

    var body: some View {
        ZStack {
            LibraryRootView()
                .opacity(libraryOpacity)
                .accessibilityHidden(showsLaunch && !libraryShown)
                .allowsHitTesting(!showsLaunch || libraryShown)
            if showsLaunch {
                LaunchOverlay(isReady: app.phase == .ready,
                              onHandOver: { withAnimation(.easeOut(duration: LaunchOverlay.handOverDuration)) { libraryShown = true } },
                              onFinished: { showsLaunch = false })
            }
        }
        .background(Color.paper.ignoresSafeArea())
        .environment(app)
        .environment(app.library)
        .environment(app.activity)
        .environment(app.flashcards)
        .modelContainer(app.container)
        .task {
            let enabled = LaunchAnimation.isEnabled
            showsLaunch = enabled && app.phase != .ready
            #if DEBUG
            if LaunchOptions.arguments.contains("-framePacing") { FramePacingWindow.install() }
            #endif
            await app.start()
            app.takeControlAction()
            await WidgetBridge.update(app)
        }
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            if let action = AppAction(spotlight: activity) { app.pendingAction = action }
        }
        .onReceive(NotificationCenter.default.publisher(for: .owlLunaControlAction).receive(on: DispatchQueue.main)) { _ in app.takeControlAction() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                app.sync.schedule(after: .seconds(1))
                app.takeControlAction()
            }
            if phase != .active {
                app.flushOpenDocuments()
                app.activity.flush()
                app.sync.schedule(after: .seconds(1))
                Task { await WidgetBridge.update(app) }
            }
        }
    }
}
