import XCTest
import PencilKit
@testable import NotesApp

/// The favourite tools: what is kept of a tool, and the shelf they are kept on.
@MainActor
final class ToolPresetTests: XCTestCase {
    /// Settings of its own for each test, taken away afterwards.
    private func freshDefaults() throws -> UserDefaults {
        let suite = "ToolPresetTests-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        return try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    func testAToolIsKeptWithItsKindColourAndWidth() throws {
        let preset = try XCTUnwrap(ToolPreset(PKInkingTool(.fountainPen, color: UIColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1), width: 6)))
        XCTAssertEqual(preset.inkType, .fountainPen)
        XCTAssertEqual(preset.color, 0x3366_CCFF)
        XCTAssertEqual(preset.width, 6, accuracy: 0.01)
        let tool = try XCTUnwrap(preset.tool)
        XCTAssertEqual(tool.inkType, .fountainPen)
        XCTAssertEqual(tool.width, 6, accuracy: 0.01)
        XCTAssertEqual(ToolPreset(tool)?.color, preset.color, "the colour comes back as it went in")
        XCTAssertNil(ToolPreset(PKEraserTool(.vector)), "only pens, pencils and markers are kept")
        XCTAssertNil(ToolPreset(PKLassoTool()))
    }

    func testAWidthPastWhatTheInkAllowsIsBroughtBackIn() throws {
        let range = PKInkingTool.InkType.monoline.validWidthRange
        let tool = try XCTUnwrap(ToolPreset(ink: .monoline, color: 0x0000_00FF, width: 500).tool)
        XCTAssertEqual(tool.width, range.upperBound, accuracy: 0.01)
        XCTAssertEqual(ToolPreset(ink: .monoline, color: 0x0000_00FF, width: 500).widthFraction, 1)
        XCTAssertEqual(ToolPreset(ink: .marker, color: 0x0000_00FF, width: PKInkingTool.InkType.marker.validWidthRange.lowerBound).widthFraction, 0)
    }

    func testTheSameToolIsToldByKindColourAndWidthNotByWhichWasSaved() {
        let pen = ToolPreset(ink: .pen, color: 0x2747_B8FF, width: 3)
        XCTAssertTrue(pen.isSameTool(as: ToolPreset(ink: .pen, color: 0x2747_B8FF, width: 3.1)))
        XCTAssertFalse(pen.isSameTool(as: ToolPreset(ink: .pencil, color: 0x2747_B8FF, width: 3)))
        XCTAssertFalse(pen.isSameTool(as: ToolPreset(ink: .pen, color: 0x2747_B9FF, width: 3)))
        XCTAssertFalse(pen.isSameTool(as: ToolPreset(ink: .pen, color: 0x2747_B8FF, width: 4)))
    }

    func testColoursAreNamedForVoiceOver() {
        func name(_ color: UInt32) -> String { ToolPreset(ink: .pen, color: color, width: 3).colorName }
        XCTAssertEqual(name(0x1B22_30FF), "Black")
        XCTAssertEqual(name(0xFFFF_FFFF), "White")
        XCTAssertEqual(name(0x8080_80FF), "Grey")
        XCTAssertEqual(name(0xC945_2FFF), "Red")
        XCTAssertEqual(name(0xE8B0_23FF), "Yellow")
        XCTAssertEqual(name(0x2747_B8FF), "Blue")
        XCTAssertEqual(name(0x3D5A_40FF), "Green")
        XCTAssertEqual(ToolPreset(ink: .marker, color: 0xE8B0_23FF, width: 20).name, "Highlighter, Yellow")
    }

    func testANewShelfStartsWithTheAppsInksAndKeepsWhatIsSaved() throws {
        let defaults = try freshDefaults()
        let shelf = ToolShelf(defaults: defaults)
        XCTAssertEqual(shelf.usable.count, ToolShelf.starters.count)
        let pencil = ToolPreset(ink: .pencil, color: 0x3D5A_40FF, width: 4)
        XCTAssertTrue(shelf.add(pencil))
        XCTAssertFalse(shelf.add(ToolPreset(ink: .pencil, color: 0x3D5A_40FF, width: 4)), "the same tool isn't kept twice")
        XCTAssertEqual(ToolShelf(defaults: defaults).usable.last?.id, pencil.id, "and it is there the next time the app opens")

        shelf.move(pencil.id, by: -1)
        XCTAssertEqual(shelf.usable.map(\.id).firstIndex(of: pencil.id), ToolShelf.starters.count - 1)
        shelf.move(pencil.id, by: 5)
        XCTAssertEqual(shelf.usable.map(\.id).firstIndex(of: pencil.id), ToolShelf.starters.count - 1, "there is nowhere that far down to go")

        let crayon = ToolPreset(ink: .crayon, color: 0xC945_2FFF, width: 30)
        shelf.replace(pencil.id, with: crayon)
        XCTAssertEqual(shelf.usable.first { $0.id == pencil.id }?.inkType, .crayon, "replaced where it stood")
        shelf.remove(pencil.id)
        XCTAssertEqual(ToolShelf(defaults: defaults).usable.count, ToolShelf.starters.count)
    }

    func testTheShelfHoldsEightAndEmptiedStaysEmpty() throws {
        let defaults = try freshDefaults()
        let shelf = ToolShelf(defaults: defaults)
        for width in 0..<10 { shelf.add(ToolPreset(ink: .pen, color: 0x0000_00FF, width: 1 + Double(width))) }
        XCTAssertEqual(shelf.usable.count, ToolShelf.limit)
        XCTAssertTrue(shelf.isFull)
        for preset in shelf.presets { shelf.remove(preset.id) }
        XCTAssertTrue(ToolShelf(defaults: defaults).presets.isEmpty, "the starters don't come back once they have been taken off")
    }

    func testTheBarGivesTheToolsWhatTheyNeedOrWhatItHas() {
        XCTAssertEqual(ToolTray.width(for: 4, in: 300), 4 * ToolTray.slot + ToolTray.slot + 8, "four tools and the empty label")
        XCTAssertEqual(ToolTray.width(for: 8, in: 400), 8 * ToolTray.slot + 8, "a full shelf has no empty label")
        XCTAssertEqual(ToolTray.width(for: 8, in: 170), 170, "short of room, the tools scroll in what there is")
        XCTAssertNil(ToolTray.width(for: 8, in: 80), "less than two tools wide, they stay out of the bar")
        XCTAssertEqual(ToolTray.width(for: 0, in: 60), ToolTray.slot + 8, "an empty shelf still shows where a tool is saved")
    }

    func testAToolOfAKindThisBuildDoesNotKnowIsKeptAndLeftOut() throws {
        let defaults = try freshDefaults()
        let stored = #"[{"id":"\#(UUID().uuidString)","ink":"com.apple.ink.future","color":255,"width":3},{"id":"\#(UUID().uuidString)","ink":"com.apple.ink.pen","color":255,"width":3}]"#
        defaults.set(Data(stored.utf8), forKey: SettingsKey.toolPresets)
        let shelf = ToolShelf(defaults: defaults)
        XCTAssertEqual(shelf.presets.count, 2)
        XCTAssertEqual(shelf.usable.count, 1)
        shelf.add(ToolPreset(ink: .marker, color: 0xE8B0_23FF, width: 20))
        XCTAssertEqual(ToolShelf(defaults: defaults).presets.first?.ink, "com.apple.ink.future", "saving again doesn't drop it")
    }

    func testThePickerTakesASavedToolWhole() throws {
        let document = try makeDocument()
        let session = EditorSession(document: document)
        let picker = PKToolPicker()
        let controller = PageStackController(session: session, toolPicker: picker)
        controller.loadViewIfNeeded()
        let marker = ToolPreset(ink: .marker, color: 0xE8B0_23FF, width: 24)
        controller.useTool(marker)
        let chosen = try XCTUnwrap((picker.selectedToolItem as? PKToolPickerInkingItem)?.inkingTool)
        XCTAssertEqual(chosen.inkType, .marker)
        XCTAssertEqual(chosen.width, 24, accuracy: 0.01)
        XCTAssertEqual(ToolPreset(chosen)?.color, marker.color)
        XCTAssertTrue(session.currentTool?.isSameTool(as: marker) ?? false, "and the tray is told which tool is in use")
    }

    private func makeDocument() throws -> NotebookDocument {
        let root = StorageRoot(url: FileManager.default.temporaryDirectory.appending(path: "tool-tests-\(UUID().uuidString)", directoryHint: .isDirectory))
        let defaults = PageDefaults(template: .blank, paperColor: .white, pageSize: .letter)
        let manifest = NotebookManifest(title: "Tools", defaults: defaults, pages: [defaults.newPage()])
        let package = NotebookPackage(root: root, id: manifest.id)
        return NotebookDocument(package: package, load: ManifestLoad(manifest: manifest))
    }
}
