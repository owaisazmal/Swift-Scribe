import UIKit

/// What a canvas returns as its `undoManager`. PencilKit registers each stroke inside its own group (and calls
/// private grouping API), so it gets a throwaway stack here that is cleared after every group. Undo and redo,
/// from the tool picker, keyboard or gestures, are forwarded to the document's single stack.
final class CanvasUndoProxy: UndoManager {
    private weak var document: UndoManager?
    private var purgeScheduled = false
    /// While a recording is replayed the page shows ink as it was, so nothing is undone under it.
    var isSuspended = false
    /// Only read again in deinit, when nothing else can reach it.
    nonisolated(unsafe) private var relays: [NSObjectProtocol] = []

    init(document: UndoManager) {
        self.document = document
        super.init()
        levelsOfUndo = 1
        let center = NotificationCenter.default
        for name in [Notification.Name.NSUndoManagerDidCloseUndoGroup, .NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange] {
            relays.append(center.addObserver(forName: name, object: document, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    NotificationCenter.default.post(name: .scribeUndoStateDidChange, object: self)
                }
            })
        }
    }

    deinit {
        relays.forEach(NotificationCenter.default.removeObserver)
    }

    override var canUndo: Bool { !isSuspended && document?.canUndo ?? false }
    override var canRedo: Bool { !isSuspended && document?.canRedo ?? false }
    override var undoActionName: String { document?.undoActionName ?? "" }
    override var redoActionName: String { document?.redoActionName ?? "" }
    override var undoMenuItemTitle: String { document?.undoMenuItemTitle ?? super.undoMenuItemTitle }
    override var redoMenuItemTitle: String { document?.redoMenuItemTitle ?? super.redoMenuItemTitle }
    override func undo() { if !isSuspended { document?.undo() } }
    override func redo() { if !isSuspended { document?.redo() } }

    override func endUndoGrouping() {
        super.endUndoGrouping()
        guard groupingLevel == 0, !purgeScheduled else { return }
        purgeScheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.purgeScheduled = false
                if self.groupingLevel == 0 { self.removeAllActions() }
            }
        }
    }
}

extension Notification.Name {
    static let scribeUndoStateDidChange = Notification.Name("ScribeUndoStateDidChange")
}
