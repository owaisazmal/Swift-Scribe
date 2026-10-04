import UIKit
import PencilKit
import Observation

/// A pen, pencil or marker kept for later: its kind, its colour and its width.
struct ToolPreset: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    /// PencilKit's own name for the kind of ink, so a kind this build doesn't know is kept and left out.
    var ink: String
    /// Red, green, blue and alpha, a byte each, as the ink is on light paper.
    var color: UInt32
    var width: Double

    init(id: UUID = UUID(), ink: PKInkingTool.InkType, color: UInt32, width: Double) {
        self.id = id
        self.ink = ink.rawValue
        self.color = color
        self.width = width
    }

    /// The tool as it is now in the picker or on a canvas; nil for the eraser, the lasso and the ruler.
    init?(_ tool: PKTool) {
        guard let inking = tool as? PKInkingTool else { return nil }
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        inking.color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func byte(_ value: CGFloat) -> UInt32 { UInt32((min(max(value, 0), 1) * 255).rounded()) }
        self.init(ink: inking.inkType, color: byte(red) << 24 | byte(green) << 16 | byte(blue) << 8 | byte(alpha), width: inking.width)
    }

    var inkType: PKInkingTool.InkType? { PKInkingTool.InkType(rawValue: ink) }

    var uiColor: UIColor {
        UIColor(red: CGFloat(color >> 24 & 0xFF) / 255, green: CGFloat(color >> 16 & 0xFF) / 255,
                blue: CGFloat(color >> 8 & 0xFF) / 255, alpha: CGFloat(color & 0xFF) / 255)
    }

    var tool: PKInkingTool? {
        guard let inkType else { return nil }
        let range = inkType.validWidthRange
        return PKInkingTool(inkType, color: uiColor, width: min(max(width, range.lowerBound), range.upperBound))
    }

    /// Where the width lies in what this kind of ink allows, from 0 to 1.
    var widthFraction: Double {
        guard let range = inkType?.validWidthRange, range.upperBound > range.lowerBound else { return 0.5 }
        return min(max((width - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
    }

    /// The same tool, whichever one of them was saved.
    func isSameTool(as other: ToolPreset) -> Bool {
        ink == other.ink && color == other.color && abs(width - other.width) < 0.15
    }

    var kindName: String {
        switch inkType {
        case .pen: String(localized: "Pen")
        case .pencil: String(localized: "Pencil")
        case .marker: String(localized: "Highlighter")
        case .monoline: String(localized: "Fineliner")
        case .fountainPen: String(localized: "Fountain Pen")
        case .watercolor: String(localized: "Watercolour")
        case .crayon: String(localized: "Crayon")
        default: String(localized: "Calligraphy Pen")
        }
    }

    var symbol: String {
        switch inkType {
        case .pen: "pencil.tip"
        case .pencil: "pencil"
        case .marker: "highlighter"
        case .monoline: "pencil.line"
        case .watercolor: "paintbrush"
        case .crayon: "scribble"
        default: "paintbrush.pointed"
        }
    }

    /// The colour in a word, for VoiceOver and the Large Content Viewer.
    var colorName: String {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        uiColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        if brightness < 0.2 { return String(localized: "Black") }
        if saturation < 0.12 { return brightness > 0.9 ? String(localized: "White") : String(localized: "Grey") }
        switch hue * 360 {
        case ..<15, 345...: return String(localized: "Red")
        case ..<40: return brightness < 0.6 ? String(localized: "Brown") : String(localized: "Orange")
        case ..<65: return String(localized: "Yellow")
        case ..<165: return String(localized: "Green")
        case ..<195: return String(localized: "Teal")
        case ..<255: return String(localized: "Blue")
        case ..<290: return String(localized: "Purple")
        default: return String(localized: "Pink")
        }
    }

    /// "Pen, Blue".
    var name: String { String(localized: "\(kindName), \(colorName)") }
}

/// The favourite tools, the same in every notebook and window. Kept in the app's settings.
@MainActor
@Observable
final class ToolShelf {
    static let shared = ToolShelf()
    static let limit = 8

    /// A new shelf starts with the app's own inks.
    static let starters = [ToolPreset(ink: .pen, color: 0x1B22_30FF, width: 2.7), ToolPreset(ink: .pen, color: 0x2747_B8FF, width: 2.7),
                           ToolPreset(ink: .pen, color: 0xC945_2FFF, width: 2.7), ToolPreset(ink: .marker, color: 0xE8B0_23FF, width: 20)]

    private(set) var presets: [ToolPreset]
    @ObservationIgnored private let defaults: UserDefaults?

    /// Without `defaults` the shelf lasts as long as the app does.
    init(defaults: UserDefaults? = .standard) {
        var store = defaults
        #if DEBUG
        if LaunchOptions.arguments.contains("-freshToolPresets") { store = nil }
        #endif
        self.defaults = store
        presets = store?.data(forKey: SettingsKey.toolPresets).flatMap { try? JSONDecoder().decode([ToolPreset].self, from: $0) } ?? Self.starters
    }

    /// The tools this build can use; one of a kind it doesn't know stays saved and isn't shown.
    var usable: [ToolPreset] { presets.filter { $0.inkType != nil } }

    var isFull: Bool { usable.count >= Self.limit }

    func holds(_ tool: ToolPreset) -> Bool { presets.contains { $0.isSameTool(as: tool) } }

    @discardableResult
    func add(_ tool: ToolPreset) -> Bool {
        guard !isFull, !holds(tool), tool.inkType != nil else { return false }
        presets.append(tool)
        save()
        return true
    }

    func replace(_ id: UUID, with tool: ToolPreset) {
        guard let index = presets.firstIndex(where: { $0.id == id }), !holds(tool) else { return }
        presets[index] = tool
        presets[index].id = id
        save()
    }

    func remove(_ id: UUID) {
        presets.removeAll { $0.id == id }
        save()
    }

    /// One place up or down among the tools that are shown.
    func move(_ id: UUID, by step: Int) {
        let shown = usable
        guard let from = shown.firstIndex(where: { $0.id == id }), shown.indices.contains(from + step),
              let source = presets.firstIndex(where: { $0.id == id }),
              let target = presets.firstIndex(where: { $0.id == shown[from + step].id }) else { return }
        presets.swapAt(source, target)
        save()
    }

    private func save() {
        guard let defaults, let data = try? JSONEncoder().encode(presets) else { return }
        defaults.set(data, forKey: SettingsKey.toolPresets)
    }
}
