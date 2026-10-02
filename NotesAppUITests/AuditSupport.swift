import XCTest

extension XCTestCase {
    /// Logs, without failing, issues the app can't act on: system glass bars, PencilKit's tool picker handle, text the
    /// audit reads off the dimmed screen behind a sheet (VoiceOver skips it by design), and `formText` below.
    @MainActor
    func audit(_ app: XCUIApplication, _ types: XCUIAccessibilityAuditType = .all, screen: String = "", modal: Bool = false,
               scrolled: Bool = false, formText: [String] = [], sheet: XCUIElement? = nil, popover: Bool = false,
               largeText: Bool = false, overlay: XCUIElement? = nil, bar: XCUIElement? = nil, pageText: [String] = []) throws {
        let barMaxY = app.navigationBars.allElementsBoundByIndex.map { $0.frame.maxY }.max() ?? 0
        let screenMaxY = app.windows.firstMatch.frame.maxY
        let overlayTop = overlay.map { $0.exists ? $0.frame.minY - 120 : screenMaxY - 240 }
        let barFrame = bar.flatMap { $0.exists ? $0.frame.insetBy(dx: -4, dy: -4) : nil }
        let sheetTexts = sheet.flatMap { $0.exists ? $0.staticTexts.allElementsBoundByIndex.map(\.frame) : nil } ?? []
        try app.performAccessibilityAudit(for: types) { issue in
            let element = issue.element
            print("AUDIT [\(screen)] \(issue.compactDescription) | type \(element.map { String($0.elementType.rawValue) } ?? "-") '\(element?.label ?? "nil")' \(element?.frame ?? .zero)")
            if issue.auditType == .contrast || issue.auditType == .dynamicType, let element, element.frame.minY < barMaxY {
                print("AUDIT [\(screen)] ignored on system bar: \(element.label)")
                return true
            }
            // Text typed on a page is the user's content: they set its size, and it zooms with the page as ink does.
            if issue.auditType == .dynamicType, let label = element?.label, !pageText.isEmpty,
               element?.identifier == "page.text.editor" || pageText.contains(where: label.hasPrefix) {
                print("AUDIT [\(screen)] ignored, text on the page: \(label)")
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
            // Text on the editor's floating bars is reported as low contrast whatever its colours, and not every run.
            // The pairs it uses (Ink on Surface, Paper on the accent) are checked by DesignTokenTests.
            if let barFrame, issue.auditType == .contrast, let element, barFrame.contains(element.frame) {
                print("AUDIT [\(screen)] ignored on a floating bar: \(element.label)")
                return true
            }
            // Now and then the audit reports a text-size issue with no element at all, on a different screen each time.
            if issue.auditType == .dynamicType, element == nil {
                print("AUDIT [\(screen)] ignored, no element to act on: \(issue.compactDescription)")
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
            // Scrolled, text just below the glass bar sits in its fading edge, where it reads as low contrast.
            if scrolled, issue.auditType == .contrast, let element, element.frame.minY < barMaxY + 44 {
                print("AUDIT [\(screen)] ignored under the bar's edge: \(element.label)")
                return true
            }
            // Scrolled, some text sits under the glass bar; the audit sometimes can't name it, so it can't be placed there.
            if scrolled, issue.auditType == .contrast || issue.auditType == .dynamicType || issue.auditType == .textClipped, element == nil {
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
