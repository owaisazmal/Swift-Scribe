import Foundation
import CoreGraphics
import CoreText
import ImageIO

// Generates the app icon sets, the Settings previews and docs/icon-sheet.png.
// swiftc -O Scripts/AppIcon/*.swift -o .build/make-icon && .build/make-icon NotesApp/Assets.xcassets docs

/// The same variable instances as `ScribeFonts.coverLabel` and `printTitle` in the app.
enum IconFonts {
    private static let soft = 0x534F_4654 as UInt32
    private static let wonk = 0x574F_4E4B as UInt32
    private static let weight = 0x7767_6874 as UInt32
    private static let width = 0x7764_7468 as UInt32
    private static let opticalSize = 0x6F70_737A as UInt32

    static func register(_ urls: [URL]) {
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true) { errors, _ in
            for error in (errors as? [CFError]) ?? [] { fail("font registration failed: \(error)") }
            return true
        }
        for (font, family) in [(coverLabel(size: 100), "Fraunces"), (printTitle(size: 100), "Bricolage Grotesque")]
        where CTFontCopyFamilyName(font) as String != family {
            fail("\(family) isn't available")
        }
    }

    static func coverLabel(size: CGFloat) -> CTFont {
        variable("Fraunces-SemiBold", size: size, axes: [weight: 600, soft: 50, wonk: 1, opticalSize: min(max(size, 9), 144)])
    }

    static func printTitle(size: CGFloat) -> CTFont {
        variable("BricolageGrotesque-96ptExtraBold", size: size, axes: [weight: 800, width: 75, opticalSize: min(max(size, 12), 96)])
    }

    static func interface(size: CGFloat) -> CTFont {
        CTFontCreateUIFontForLanguage(.system, size, nil)!
    }

    private static func variable(_ name: String, size: CGFloat, axes: [UInt32: CGFloat]) -> CTFont {
        let variations = Dictionary(uniqueKeysWithValues: axes.map { (NSNumber(value: $0.key), NSNumber(value: Double($0.value))) })
        let attributes: [CFString: Any] = [kCTFontNameAttribute: name, kCTFontVariationAttribute: variations]
        return CTFontCreateWithFontDescriptor(CTFontDescriptorCreateWithAttributes(attributes as CFDictionary), size, nil)
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("make-icon: \(message)\n".utf8))
    exit(1)
}

// MARK: Bitmaps

func bitmap(_ width: Int, _ height: Int, opaque: Bool = false) -> CGContext {
    let alpha = opaque ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast
    guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                              bitmapInfo: alpha.rawValue) else { fail("couldn't make a \(width)×\(height) bitmap") }
    ctx.interpolationQuality = .high
    return ctx
}

func icon(_ cloth: IconCloth, _ variant: IconVariant, size: Int = 1024) -> CGImage {
    let ctx = bitmap(size, size, opaque: variant == .light)
    IconArt.draw(in: ctx, size: CGFloat(size), variant: variant, cloth: cloth)
    return ctx.makeImage()!
}

/// Halves until close, then draws at the target size, so fine texture averages out instead of aliasing.
func downscale(_ image: CGImage, to size: Int, opaque: Bool = false) -> CGImage {
    var current = image
    while current.width / 2 >= size * 2 {
        let ctx = bitmap(current.width / 2, current.height / 2)
        ctx.draw(current, in: CGRect(x: 0, y: 0, width: ctx.width, height: ctx.height))
        current = ctx.makeImage()!
    }
    let ctx = bitmap(size, size, opaque: opaque)
    ctx.draw(current, in: CGRect(x: 0, y: 0, width: size, height: size))
    return ctx.makeImage()!
}

/// The dark Home Screen puts dark icons on a near-black gradient.
func onDarkBackdrop(_ image: CGImage) -> CGImage {
    let ctx = bitmap(image.width, image.height)
    let gradient = CGGradient(colorsSpace: sRGB, colors: [gray(0.2), gray(0.07)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: CGFloat(image.height)), end: .zero, options: [])
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return ctx.makeImage()!
}

/// An approximation of the tinted Home Screen: luminance becomes the tint, over a dark wash of it.
func tinted(_ image: CGImage, tint: (CGFloat, CGFloat, CGFloat)) -> CGImage {
    let ctx = bitmap(image.width, image.height)
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let pixels = ctx.data!.bindMemory(to: UInt8.self, capacity: ctx.bytesPerRow * ctx.height)
    for y in 0..<ctx.height {
        for x in 0..<ctx.width {
            let p = pixels + y * ctx.bytesPerRow + x * 4
            let lum = CGFloat(p[0]) * 0.2126 + CGFloat(p[1]) * 0.7152 + CGFloat(p[2]) * 0.0722
            p[0] = UInt8(lum * tint.0); p[1] = UInt8(lum * tint.1); p[2] = UInt8(lum * tint.2)
        }
    }
    let foreground = ctx.makeImage()!
    let result = bitmap(image.width, image.height)
    let wash = CGGradient(colorsSpace: sRGB, colors: [CGColor(srgbRed: tint.0 * 0.3, green: tint.1 * 0.3, blue: tint.2 * 0.3, alpha: 1),
                                                     CGColor(srgbRed: tint.0 * 0.12, green: tint.1 * 0.12, blue: tint.2 * 0.12, alpha: 1)] as CFArray,
                          locations: [0, 1])!
    result.drawLinearGradient(wash, start: CGPoint(x: 0, y: CGFloat(image.height)), end: .zero, options: [])
    result.draw(foreground, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return result.makeImage()!
}

func write(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { fail("can't write \(url.path)") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fail("can't write \(url.path)") }
}

func writeJSON(_ object: [String: Any], to url: URL) {
    do {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try (data + Data("\n".utf8)).write(to: url)
    } catch { fail("can't write \(url.path): \(error)") }
}

func folder(_ url: URL) -> URL {
    do { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) } catch { fail("can't create \(url.path)") }
    return url
}

// MARK: Sheet

/// The Home Screen's icon shape, near enough for the review sheet.
func iconMask(_ rect: CGRect) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: rect.width * 0.225, cornerHeight: rect.height * 0.225, transform: nil)
}

func text(_ string: String, font: CTFont, color: CGColor, at point: CGPoint, in ctx: CGContext) {
    let attributes = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color] as CFDictionary
    let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, string as CFString, attributes))
    ctx.textPosition = point
    CTLineDraw(line, ctx)
}

func sheet(_ icons: [IconCloth: [IconVariant: CGImage]]) -> CGImage {
    let margin: CGFloat = 56, nameWidth: CGFloat = 180, large: CGFloat = 224, gap: CGFloat = 28
    let small: [CGFloat] = [152, 120, 80, 58, 40]
    let rowHeight = large + 48, header: CGFloat = 132
    let width = margin * 2 + nameWidth + (large + gap) * 3 + small.reduce(0, +) + CGFloat(small.count - 1) * 24
    let height = margin * 2 + header + rowHeight * CGFloat(IconCloth.allCases.count)
    let ctx = bitmap(Int(width), Int(height), opaque: true)
    ctx.setFillColor(rgb(0xF1EDE4))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let ink = rgb(0x1B2230), secondary = rgb(0x5A6070)

    func place(_ image: CGImage, size: CGFloat, x: CGFloat, top: CGFloat) {
        let rect = CGRect(x: x, y: height - top - size, width: size, height: size)
        ctx.saveGState()
        ctx.addPath(iconMask(rect))
        ctx.clip()
        ctx.draw(downscale(image, to: Int(size)), in: rect)
        ctx.restoreGState()
    }

    text("Swift Scribe · Clothbound app icon", font: IconFonts.coverLabel(size: 44), color: ink, at: CGPoint(x: margin, y: height - margin - 44), in: ctx)
    let columns = ["Light", "Dark", "Tinted"]
    for (index, title) in columns.enumerated() {
        text(title.uppercased(), font: IconFonts.interface(size: 17), color: secondary,
             at: CGPoint(x: margin + nameWidth + (large + gap) * CGFloat(index), y: height - margin - header + 22), in: ctx)
    }
    text("HOME SCREEN SIZES, LIGHT (PX)", font: IconFonts.interface(size: 17), color: secondary,
         at: CGPoint(x: margin + nameWidth + (large + gap) * 3, y: height - margin - header + 22), in: ctx)

    for (row, cloth) in IconCloth.allCases.enumerated() {
        let top = margin + header + rowHeight * CGFloat(row)
        text(cloth.name, font: IconFonts.coverLabel(size: 34), color: ink, at: CGPoint(x: margin, y: height - top - large / 2 - 12), in: ctx)
        guard let set = icons[cloth] else { continue }
        place(set[.light]!, size: large, x: margin + nameWidth, top: top)
        place(onDarkBackdrop(set[.dark]!), size: large, x: margin + nameWidth + large + gap, top: top)
        place(tinted(set[.tinted]!, tint: (0.93, 0.72, 0.36)), size: large, x: margin + nameWidth + (large + gap) * 2, top: top)
        var x = margin + nameWidth + (large + gap) * 3
        for size in small {
            place(set[.light]!, size: size, x: x, top: top + (large - size) / 2)
            text("\(Int(size))", font: IconFonts.interface(size: 14), color: secondary, at: CGPoint(x: x, y: height - top - large - 22), in: ctx)
            x += size + 24
        }
    }
    return ctx.makeImage()!
}

// MARK: Main

let arguments = CommandLine.arguments
guard arguments.count == 3 else { fail("usage: make-icon <Assets.xcassets> <docs folder>") }
let catalog = URL(fileURLWithPath: arguments[1], isDirectory: true)
let docs = URL(fileURLWithPath: arguments[2], isDirectory: true)
let fonts = catalog.deletingLastPathComponent().appending(path: "Resources/Fonts")
IconFonts.register([fonts.appending(path: "Fraunces[SOFT,WONK,opsz,wght].ttf"), fonts.appending(path: "BricolageGrotesque[opsz,wdth,wght].ttf")])

let info: [String: Any] = ["author": "xcode", "version": 1]
var rendered: [IconCloth: [IconVariant: CGImage]] = [:]
for cloth in IconCloth.allCases {
    let set = folder(catalog.appending(path: "\(cloth.setName).appiconset"))
    var images: [[String: Any]] = []
    for variant in IconVariant.allCases {
        let image = icon(cloth, variant)
        rendered[cloth, default: [:]][variant] = image
        let file = variant == .light ? "\(cloth.setName).png" : "\(cloth.setName)-\(variant.rawValue.capitalized).png"
        write(image, to: set.appending(path: file))
        var entry: [String: Any] = ["filename": file, "idiom": "universal", "platform": "ios", "size": "1024x1024"]
        if variant != .light { entry["appearances"] = [["appearance": "luminosity", "value": variant.rawValue]] }
        images.append(entry)
    }
    writeJSON(["images": images, "info": info], to: set.appending(path: "Contents.json"))

    let preview = "IconPreview-\(cloth.name)"
    let previews = folder(catalog.appending(path: "\(preview).imageset"))
    write(downscale(rendered[cloth]![.light]!, to: 180, opaque: true), to: previews.appending(path: "\(preview).png"))
    write(downscale(onDarkBackdrop(rendered[cloth]![.dark]!), to: 180, opaque: true), to: previews.appending(path: "\(preview)-Dark.png"))
    writeJSON(["images": [["filename": "\(preview).png", "idiom": "universal"],
                          ["appearances": [["appearance": "luminosity", "value": "dark"]], "filename": "\(preview)-Dark.png", "idiom": "universal"]],
               "info": info], to: previews.appending(path: "Contents.json"))
}
write(sheet(rendered), to: folder(docs).appending(path: "icon-sheet.png"))
print("make-icon: wrote \(IconCloth.allCases.count) icon sets, previews and \(docs.lastPathComponent)/icon-sheet.png")
