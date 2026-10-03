import XCTest

@MainActor
extension XCUIApplication {
    /// The element carrying an accessibility identifier, whatever kind of element it is.
    func element(_ identifier: String) -> XCUIElement {
        descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// The library's search field, emptied and ready for typing.
    @discardableResult
    func openLibrarySearch() -> XCUIElement {
        let field = element("library.search")
        XCTAssertTrue(field.waitForExistence(timeout: 5), "library search")
        field.tap()
        let clear = buttons["library.search.clear"]
        if clear.exists { clear.tap() }
        return field
    }
}
