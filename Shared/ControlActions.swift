import AppIntents
import Foundation

/// What a Control Center button asked for, left in the shared container for the app to pick up as it comes to the front.
enum ControlRelay {
    static let key = "pendingControlAction"

    static var defaults: UserDefaults? { UserDefaults(suiteName: WidgetSnapshot.appGroup) }

    static func post(_ action: String, to defaults: UserDefaults? = ControlRelay.defaults) {
        defaults?.set(action, forKey: key)
        NotificationCenter.default.post(name: .scribeControlAction, object: nil)
    }

    /// The action waiting, if any. Taking it clears it, so it is carried out once.
    static func take(from defaults: UserDefaults? = ControlRelay.defaults) -> String? {
        guard let action = defaults?.string(forKey: key) else { return nil }
        defaults?.removeObject(forKey: key)
        return action
    }
}

extension Notification.Name {
    static let scribeControlAction = Notification.Name("ScribeControlAction")
}

struct QuickNoteControlIntent: AppIntent {
    static let title: LocalizedStringResource = "New Quick Note"
    static let openAppWhenRun = true
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        ControlRelay.post("quicknote")
        return .result()
    }
}

struct TodayPageControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Today's Journal Page"
    static let openAppWhenRun = true
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        ControlRelay.post("today")
        return .result()
    }
}
