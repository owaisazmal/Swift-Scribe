import XCTest
@testable import OwlLuna

/// With a keyboard attached the system has the page stack's anchor resign when keyboard focus moves, as when a menu closes.
@MainActor
final class ResponderAnchorTests: XCTestCase {
    private final class Holder: UIView {
        override var canBecomeFirstResponder: Bool { true }
    }

    private func settled(_ condition: () -> Bool) async throws -> Bool {
        let deadline = Date().addingTimeInterval(2)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        try await Task.sleep(for: .milliseconds(60))
        return condition()
    }

    func testTheAnchorTakesFirstResponderBackUnlessSomethingElseHoldsIt() async throws {
        let root = temporaryRoot(self)
        let manifest = NotebookManifest(title: "Biology", defaults: PageDefaults(template: .narrowRuled, paperColor: .white, pageSize: .letter),
                                        pages: [.template(.blank, color: .white, size: .letter)])
        try await NotebookPackage(root: root, id: manifest.id).create(manifest)
        let session = EditorSession(document: try await NotebookDocument.open(manifest.id, root: root))
        let controller = PageStackController(session: session)
        session.canvas = controller
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 834, height: 1194)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        addTeardownBlock { @MainActor in window.isHidden = true }
        controller.view.layoutIfNeeded()

        let anchor = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? ResponderAnchor }.first)
        let holdsAnchor = { anchor.isFirstResponder }
        let appeared = try await settled(holdsAnchor)
        XCTAssertTrue(appeared, "the anchor is first responder once the pages are on screen")

        anchor.resignFirstResponder()
        XCTAssertFalse(holdsAnchor())
        let reclaimed = try await settled(holdsAnchor)
        XCTAssertTrue(reclaimed, "given up with nothing taking its place, it is taken back")

        let holder = Holder()
        controller.view.addSubview(holder)
        XCTAssertTrue(holder.becomeFirstResponder())
        let stolen = try await settled(holdsAnchor)
        XCTAssertFalse(stolen, "another responder keeps what it took")
        XCTAssertTrue(holder.isFirstResponder)

        controller.setModalShowing(true)
        holder.resignFirstResponder()
        let duringModal = try await settled(holdsAnchor)
        XCTAssertFalse(duringModal, "nothing is taken back under a sheet")
        controller.setModalShowing(false)
        XCTAssertTrue(holdsAnchor())
    }
}
