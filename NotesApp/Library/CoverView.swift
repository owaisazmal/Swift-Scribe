import SwiftUI
import UniformTypeIdentifiers
import CoreTransferable

extension UTType {
    static let notebookReference = UTType(exportedAs: "com.owais.swiftscribe.notebook-reference")
}

/// What a dragged notebook carries: its identity, typed so it can't be pasted into another app as text.
struct NotebookReference: Codable, Transferable, Hashable {
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .notebookReference)
    }
}

/// Renders covers in a few fixed widths so the cache is shared across the library, the spread and sheets.
enum CoverWidth {
    static let shelf: CGFloat = 176
    static let spread: CGFloat = 220
    static let preview: CGFloat = 260
    static let row: CGFloat = 64
}

struct CoverView: View {
    let request: CoverRequest
    /// False for the live preview, whose every keystroke would otherwise fill the caches.
    var persist = true
    var showsShadow = true
    var prepareFirstPage: (@MainActor () async -> Void)?
    @State private var image: UIImage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    init(request: CoverRequest, persist: Bool = true, showsShadow: Bool = true, prepareFirstPage: (@MainActor () async -> Void)? = nil) {
        self.request = request
        self.persist = persist
        self.showsShadow = showsShadow
        self.prepareFirstPage = prepareFirstPage
        _image = State(initialValue: CoverCache.shared.cached(request.key))
    }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: Radius.coverSpine, bottomLeadingRadius: Radius.coverSpine,
                               bottomTrailingRadius: Radius.coverEdge, topTrailingRadius: Radius.coverEdge)
    }

    var body: some View {
        Color.clear
            .aspectRatio(3 / 4, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().interpolation(.high).transition(.opacity)
                } else {
                    shape.fill(placeholder)
                }
            }
            .overlay { if contrast == .increased { shape.strokeBorder(Color.hairline, lineWidth: 1) } }
            .background { if showsShadow { CoverShadowView() } }
            .task(id: request.key) {
                if let hit = CoverCache.shared.cached(request.key) { image = hit; return }
                if !persist {
                    try? await Task.sleep(for: .milliseconds(120))
                    guard !Task.isCancelled else { return }
                }
                if request.spec.style == .firstPage, let file = request.firstPage,
                   !FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) {
                    await prepareFirstPage?()
                }
                if let rendered = await CoverCache.shared.image(for: request, persist: persist) {
                    withAnimation(Motion.adaptive(Motion.quick, reduceMotion: reduceMotion)) { image = rendered }
                }
            }
            .accessibilityHidden(true)
    }

    private var placeholder: Color {
        switch request.spec.style {
        case .cloth: request.spec.cloth.color
        case .print: Color(hex: RisoInk.paperStock)
        case .firstPage: .white
        }
    }
}

struct FavoriteRibbon: View {
    var body: some View {
        RibbonShape()
            .fill(Color.tomato)
            .overlay { RibbonShape().stroke(Color.labelCream, lineWidth: 1.5) }
            .frame(width: 14, height: 42)
            .shadow(color: .black.opacity(0.2), radius: 0.5, y: 0.5)
            .accessibilityHidden(true)
    }
}

extension NotebookRecord {
    @MainActor
    func coverRequest(width: CGFloat, scale: CGFloat, colorScheme: ColorScheme, contrast: ColorSchemeContrast, root: StorageRoot,
                      spec: CoverSpec? = nil) -> CoverRequest {
        let spec = spec ?? cover
        let package = NotebookPackage(root: root, id: id)
        let thumbKey = firstPageThumbKey ?? "none"
        let thumb = firstPageID.map { package.thumbURL($0, key: thumbKey) }
        return CoverRequest(notebookID: id, spec: spec, title: title.isEmpty ? String(localized: "Untitled") : title,
                            meta: folder?.name ?? createdAt.formatted(.dateTime.month(.abbreviated).year()), width: width, scale: scale,
                            dark: colorScheme == .dark, highContrast: contrast == .increased, firstPage: thumb,
                            firstPageKey: spec.style == .firstPage ? "\(firstPageID?.uuidString ?? "")-\(thumbKey)" : nil,
                            firstPageIsPDF: firstPageIsPDF)
    }

    var pageCountText: String {
        pageCount == 1 ? String(localized: "1 page") : String(localized: "\(pageCount) pages")
    }

    var metaLine: String {
        "\(pageCountText) · \(modifiedAt.formatted(.relative(presentation: .named)))"
    }

    func accessibilityHint(isSelecting: Bool) -> String {
        if isSelecting { return String(localized: "Selects or deselects this notebook") }
        if isTrashed { return String(localized: "Deleted. Use actions to restore it or delete it permanently.") }
        return String(localized: "Opens the notebook")
    }

    var accessibilityDescription: String {
        var parts = [title.isEmpty ? String(localized: "Untitled") : title, String(localized: "notebook"),
                     pageCountText,
                     String(localized: "edited \(modifiedAt.formatted(.relative(presentation: .named)))")]
        if isFavorite { parts.append(String(localized: "favourite")) }
        if let folder { parts.append(String(localized: "in \(folder.name)")) }
        if isReadOnly { parts.append(String(localized: "read-only")) }
        if issueCount > 0 { parts.append(String(localized: "has files that couldn't be read")) }
        return parts.joined(separator: ", ")
    }
}
