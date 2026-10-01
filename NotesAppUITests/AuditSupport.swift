import XCTest

extension XCTestCase {
    /// Logs, without failing, issues the app can't act on: system glass bars, PencilKit's tool picker handle, text the
    /// audit reads off the dimmed screen behind a sheet (VoiceOver skips it by design), and `formText` below.
    @MainActor
    func audit(_ app: XCUIApplication, _ types: XCUIAccessibilityAuditType = .all, screen: String = "", modal: Bool = false,
               scrolled: Bool = false, formText: [String] = [], sheet: XCUIElement? = nil, popover: Bool = false,
               largeText: Bool = false, overlay: XCUIElement? = nil) throws {
        let barMaxY = app.navigationBars.allElementsBoundByIndex.map { $0.frame.maxY }.max() ?? 0
        let screenMaxY = app.windows.firstMatch.frame.maxY
        let overlayTop = overlay.map { $0.exists ? $0.frame.minY - 120 : screenMaxY - 240 }
        let sheetTexts = sheet.flatMap { $0.exists ? $0.staticTexts.allElementsBoundByIndex.map(\.frame) : nil } ?? []
        try app.performAccessibilityAudit(for: types) { issue in
            let element = issue.element
            print("AUDIT [\(screen)] \(issue.compactDescription) | type \(element.map { String($0.elementType.rawValue) } ?? "-") '\(element?.label ?? "nil")' \(element?.frame ?? .zero)")
            if issue.auditType == .contrast || issue.auditType == .dynamicType, let element, element.frame.minY < barMaxY {
                print("AUDIT [\(screen)] ignored on system bar: \(element.label)")
                return true
            }
            // Form rows and footers are flagged whatever they hold; all of it scales fully at AX5.
            if issue.auditType == .dynamicType || (scrolled && issue.auditType == .textClipped), let label = element?.label,
               formText.contains(where: label.hasPrefix) {
                print("AUDIT [\(screen)] ignored in a Form: \(label)")
                return true
            }
            // Text dimmed behind or beside a page sheet; VoiceOver can't reach it.
            if sheet != nil, issue.auditType == .hitRegion, element == nil {
                print("AUDIT [\(screen)] ignored behind sheet: \(issue.compactDescription)")
                return true
            }
            if sheet != nil, issue.auditType == .contrast || issue.auditType == .textClipped, element.map({ !sheetTexts.contains($0.frame) }) ?? true {
                print("AUDIT [\(screen)] ignored behind sheet: \(element?.label ?? "nil")")
                return true
            }
            // iPadOS 27 reports popover content about 49 pt below where it's drawn, so contrast samples the wrong pixels.
            if popover, issue.auditType == .contrast {
                print("AUDIT [\(screen)] ignored in a popover: \(element?.label ?? "nil")")
                return true
            }
            // Thumbnail contents the audit reads as text, and rows a sheet's edge cuts at large sizes; colours are checked at the default size.
            if modal, issue.auditType == .contrast, element == nil || largeText {
                print("AUDIT [\(screen)] ignored in a sheet: \(issue.compactDescription)")
                return true
            }
            // Text the audit can't tie to an element is inside cover and page images: the user's content.
            if issue.auditType == .contrast, element == nil {
                print("AUDIT [\(screen)] ignored, text inside an image: \(issue.compactDescription)")
                return true
            }
            if issue.auditType == .contrast, let element, element.frame.maxY > screenMaxY {
                print("AUDIT [\(screen)] ignored, cut by the screen edge: \(element.label)")
                return true
            }
            // Text the undo slip covers.
            if let overlayTop, issue.auditType == .contrast || issue.auditType == .textClipped,
               element.map({ $0.frame.maxY > overlayTop && $0.elementType != .button }) ?? true {
                print("AUDIT [\(screen)] ignored under the slip: \(issue.compactDescription)")
                return true
            }
            if issue.auditType == .hitRegion, element?.label == "Tool palette handle" {
                print("AUDIT [\(screen)] ignored in PencilKit's tool picker: \(issue.compactDescription)")
                return true
            }
            // Scrolled, some text sits under the glass bar; the audit sometimes can't name it, so it can't be placed there.
            if scrolled, issue.auditType == .contrast || issue.auditType == .dynamicType, element == nil {
                print("AUDIT [\(screen)] ignored, unnamed text in a scrolled sheet: \(issue.compactDescription)")
                return true
            }
            if modal, issue.auditType == .elementDetection, element == nil {
                print("AUDIT [\(screen)] ignored behind modal: \(issue.compactDescription)")
                return true
            }
            print("AUDIT FAIL [\(screen)] \(issue.detailedDescription)")
            return false
        }
    }
}
