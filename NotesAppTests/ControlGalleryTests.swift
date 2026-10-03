import XCTest
import SwiftUI
@testable import NotesApp

private struct ControlGallery: View {
    @State private var goTo = ""
    @State private var search = ""
    @State private var typed = "Physics"
    @State private var tab = 0
    @State private var style = 1
    @FocusState private var goFocus: Bool
    @FocusState private var searchFocus: Bool
    @FocusState private var typedFocus: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            caption("Page navigator, on Desk")
            HStack(spacing: Space.x3) {
                ScribeSearchField("Go to page", text: $goTo, systemImage: "number", focus: $goFocus).frame(width: 170)
                Spacer()
                ScribeSegmentedPicker("Show", selection: $tab, options: [0, 1], inBar: true) { Text($0 == 0 ? "Pages" : "Outline") }.fixedSize()
                Spacer()
                Button { } label: { Label("Add Page", systemImage: "plus") }.buttonStyle(.boardIcon)
                Button("Done") { }.buttonStyle(.scribe(.primary, inBar: true))
            }
            .padding(Space.x4)
            .background(Color.desk)

            caption("Library toolbar, on Paper")
            HStack(spacing: Space.x3) {
                Spacer()
                BarGroup {
                    Button { } label: { Label("Sort", systemImage: "arrow.up.arrow.down") }
                    Button { } label: { Label("New", systemImage: "plus") }
                    Button("Select") { }.buttonStyle(.plain).font(.body.weight(.semibold)).foregroundStyle(Color.ink).padding(.horizontal, Space.x3).frame(minHeight: 44)
                }
                ScribeSearchField("Search", text: $search, focus: $searchFocus).frame(width: 260)
            }
            .padding(Space.x4)
            .background(Color.paper)

            caption("Editor bar, on Desk")
            HStack(spacing: Space.x3) {
                Button { } label: { Label("Library", systemImage: "chevron.backward") }.buttonStyle(.boardIcon)
                Spacer()
                Text("Physics II 3").font(.headline).foregroundStyle(Color.ink)
                Spacer()
                BarGroup {
                    Button { } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                    Button { } label: { Label("Redo", systemImage: "arrow.uturn.forward") }.disabled(true)
                }
                BarGroup {
                    Button { } label: { Label("Add", systemImage: "plus") }
                    Button { } label: { Label("Record", systemImage: "mic") }
                    Button { } label: { Label("Recordings", systemImage: "waveform") }
                    Button { } label: { Label("Tools", systemImage: "pencil.tip.crop.circle") }
                    Button { } label: { Label("More", systemImage: "ellipsis.circle") }
                }
            }
            .padding(Space.x4)
            .background(Color.desk)

            caption("Sheet, on Surface")
            VStack(alignment: .leading, spacing: Space.x4) {
                HStack {
                    Button("Cancel") { }.buttonStyle(.scribe)
                    Spacer()
                    Text("New Notebook").font(.headline).foregroundStyle(Color.ink)
                    Spacer()
                    Button("Create") { }.buttonStyle(.scribe(.primary))
                }
                TextField("Title", text: $typed).scribeField(focused: true)
                TextField("Name", text: .constant(""), prompt: Text("Optional").foregroundStyle(Color.textSecondary)).scribeField()
                ScribeSegmentedPicker("Cover", selection: $style, options: [0, 1, 2]) { Text(["Cloth", "Print", "First Page"][$0]) }
                HStack(spacing: Space.x3) {
                    Button("New Notebook") { }.buttonStyle(.scribe(.primary))
                    Button("Import PDF") { }.buttonStyle(.scribe)
                    Button { } label: { Label("Stop", systemImage: "stop.fill") }.buttonStyle(.scribe(.destructive))
                    Button("Disabled") { }.buttonStyle(.scribe(.primary)).disabled(true)
                    Button("Disabled") { }.buttonStyle(.scribe).disabled(true)
                }
            }
            .padding(Space.x4)
            .background(Color.surface)

            caption("Floating find bar, over paper")
            HStack(spacing: 0) {
                ScribeSearchField("Find in Notebook", text: .constant("mitosis"), focus: $typedFocus).frame(width: 240)
                Text("3 of 12").font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(Color.ink).padding(.horizontal, Space.x3)
                Button { } label: { Label("Previous", systemImage: "chevron.up") }
                Button { } label: { Label("Next", systemImage: "chevron.down") }
                Button("Done") { }.buttonStyle(.scribe(.primary, compact: true)).padding(.leading, Space.x2)
            }
            .buttonStyle(.barIcon)
            .padding(.horizontal, Space.x2)
            .padding(.vertical, Space.x1)
            .board(in: Capsule())
            .frame(maxWidth: .infinity)
            .padding(Space.x6)
            .background(Color.white)
        }
        .frame(width: 900)
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.caption.weight(.semibold)).foregroundStyle(Color.textSecondary)
            .padding(.horizontal, Space.x4).padding(.vertical, Space.x2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(white: 0.5).opacity(0.25))
    }
}

@MainActor
final class ControlGalleryTests: XCTestCase {
    func testRenderGallery() async throws {
        guard let out = ProcessInfo.processInfo.environment["GALLERY_OUT"] else { throw XCTSkip("Set GALLERY_OUT to render the control gallery") }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        for (name, style, contrast) in [("light", UIUserInterfaceStyle.light, UIAccessibilityContrast.normal), ("dark", .dark, .normal),
                                        ("light-hc", .light, .high), ("dark-hc", .dark, .high)] {
            let host = UIHostingController(rootView: ControlGallery())
            host.traitOverrides.userInterfaceStyle = style
            host.traitOverrides.accessibilityContrast = contrast
            let size = host.sizeThatFits(in: CGSize(width: 900, height: 2000))
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(origin: .zero, size: size)
            window.rootViewController = host
            window.isHidden = false
            window.layoutIfNeeded()
            CATransaction.flush()
            try await Task.sleep(for: .milliseconds(600))
            let format = UIGraphicsImageRendererFormat()
            format.scale = 2
            let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            try image.pngData()?.write(to: URL(fileURLWithPath: out).appendingPathComponent("gallery-\(name).png"))
            window.isHidden = true
        }
    }
}
