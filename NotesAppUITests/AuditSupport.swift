import XCTest

extension XCTestCase {
    /// Logs, without failing, issues the app can't act on: system glass bars, PencilKit's tool picker handle, text the
    /// audit reads off the dimmed screen behind a sheet (VoiceOver skips it by design), and `formEnd` below.
    @MainActor
    func audit(_ app: XCUIApplication, _ types: XCUIAccessibilityAuditType = .all, screen: String = "", modal: Bool = false,
               scrolled: Bool = false, formEnd: [String] = []) throws {
        let barMaxY = app.navigationBars.allElementsBoundByIndex.map { $0.frame.maxY }.max() ?? 0
        try app.performAccessibilityAudit(for: types) { issue in
            let element = issue.element
            print("AUDIT [\(screen)] \(issue.compactDescription) | type \(element.map { String($0.elementType.rawValue) } ?? "-") '\(element?.label ?? "nil")' \(element?.frame ?? .zero)")
            if issue.auditType == .contrast || issue.auditType == .dynamicType, let element, element.frame.minY < barMaxY {
                print("AUDIT [\(screen)] ignored on system bar: \(element.label)")
                return true
            }
            // A Form's last row and footer are flagged whatever they hold (moving another row last moves the flag); both scale fully at AX5.
            if issue.auditType == .dynamicType, let label = element?.label, formEnd.contains(where: label.hasPrefix) {
                print("AUDIT [\(screen)] ignored at the end of a Form: \(label)")
                return true
            }
            if issue.auditType == .hitRegion, element?.label == "Tool palette handle" {
                print("AUDIT [\(screen)] ignored in PencilKit's tool picker: \(issue.compactDescription)")
                return true
            }
            // Scrolled, some text sits under the glass bar; the audit sometimes can't name it, so it can't be placed there.
            if scrolled, issue.auditType == .contrast, element == nil {
                print("AUDIT [\(screen)] ignored, unnamed text in a scrolled sheet: \(issue.compactDescription)")
                return true
            }
            if modal, issue.auditType == .elementDetection, element == nil {
                print("AUDIT [\(screen)] ignored behind modal: \(issue.compactDescription)")
                return true
            }
            return false
        }
    }
}
