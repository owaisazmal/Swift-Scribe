import SwiftUI
import CoreText
import os

enum ScribeFonts {
    static let frauncesSemiBold = "Fraunces-SemiBold"
    static let frauncesRegular = "Fraunces-Regular"
    static let bricolage = "BricolageGrotesque-96ptExtraBold"

    private static let registered = OSAllocatedUnfairLock(initialState: false)

    /// Registers the bundled display fonts for this process. The Info.plist is generated, so they can't be listed there.
    static func register() {
        let shouldRegister = registered.withLock { done -> Bool in
            defer { done = true }
            return !done
        }
        guard shouldRegister else { return }
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true) { errors, _ in
            for error in (errors as? [CFError]) ?? [] {
                Logger(subsystem: "com.owais.NotesApp", category: "fonts").error("font registration failed: \(error.localizedDescription)")
            }
            return true
        }
    }

    private static let soft = 0x534F_4654 as UInt32
    private static let wonk = 0x574F_4E4B as UInt32
    private static let weight = 0x7767_6874 as UInt32
    private static let width = 0x7764_7468 as UInt32
    private static let opticalSize = 0x6F70_737A as UInt32

    /// Fraunces as used on cloth labels: semibold, a little soft, wonky on.
    static func coverLabel(size: CGFloat) -> CTFont {
        variable(frauncesSemiBold, size: size, axes: [weight: 600, soft: 50, wonk: 1, opticalSize: min(max(size, 9), 144)])
    }

    /// Bricolage Grotesque condensed ExtraBold, for Print titles only.
    static func printTitle(size: CGFloat) -> CTFont {
        variable(bricolage, size: size, axes: [weight: 800, width: 75, opticalSize: min(max(size, 12), 96)])
    }

    private static func variable(_ name: String, size: CGFloat, axes: [UInt32: CGFloat]) -> CTFont {
        register()
        let variations = Dictionary(uniqueKeysWithValues: axes.map { (NSNumber(value: $0.key), NSNumber(value: Double($0.value))) })
        let attributes: [CFString: Any] = [kCTFontNameAttribute: name, kCTFontVariationAttribute: variations]
        return CTFontCreateWithFontDescriptor(CTFontDescriptorCreateWithAttributes(attributes as CFDictionary), size, nil)
    }
}

extension Font {
    /// Fraunces for library headings and empty states, scaled with Dynamic Type.
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
        .custom(ScribeFonts.frauncesSemiBold, size: size, relativeTo: style)
    }

    static func displayText(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(ScribeFonts.frauncesRegular, size: size, relativeTo: style)
    }
}

extension View {
    /// Small-caps metadata with tabular digits: "24 PAGES · EDITED TODAY".
    func metaStyle(_ style: Font.TextStyle = .caption) -> some View {
        font(.system(style, weight: .semibold).smallCaps().monospacedDigit())
            .tracking(0.6)
            .foregroundStyle(Color.inkSecondary)
    }
}
