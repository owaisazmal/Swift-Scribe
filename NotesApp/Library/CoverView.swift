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
    var prepareFirstPage: (@MainActor () async -> Void)?
    @State private var image: UIImage?

    init(request: CoverRequest, prepareFirstPage: (@MainActor () async -> Void)? = nil) {
        self.request = request
        self.prepareFirstPage = prepareFirstPage
        _image = State(initialValue: CoverCache.shared.cached(request.key))
    }

    var body: some View {
        Color.clear
            .aspectRatio(3 / 4, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().interpolation(.high)
                } else {
                    Rectangle().fill(placeholder)
                }
            }
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: Radius.coverSpine, bottomLeadingRadius: Radius.coverSpine,
                                              bottomTrailingRadius: Radius.coverEdge, topTrailingRadius: Radius.coverEdge))
            .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
            .task(id: request.key) {
                guard image == nil || CoverCache.shared.cached(request.key) == nil else { return }
                if request.spec.style == .firstPage, let file = request.firstPage,
                   !FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) {
                    await prepareFirstPage?()
                }
                image = await CoverCache.shared.image(for: request)
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
    func coverRequest(width: CGFloat, scale: CGFloat, colorScheme: ColorScheme, contrast: ColorSchemeContrast, root: StorageRoot) -> CoverRequest {
        let package = NotebookPackage(root: root, id: id)
        let thumb = firstPageID.map { package.thumbURL($0, hash: firstPageInkHash) }
        return CoverRequest(notebookID: id, spec: cover, title: title.isEmpty ? String(localized: "Untitled") : title,
                            meta: folder?.name ?? String(localized: "\(pageCount) pages"), width: width, scale: scale,
                            dark: colorScheme == .dark, highContrast: contrast == .increased, firstPage: thumb,
                            firstPageKey: coverStyle == .firstPage ? "\(firstPageID?.uuidString ?? "")-\(firstPageInkHash ?? "")" : nil,
                            firstPageIsPDF: firstPageIsPDF)
    }

    var metaLine: String {
        let pages = pageCount == 1 ? String(localized: "1 page") : String(localized: "\(pageCount) pages")
        return "\(pages) · \(modifiedAt.formatted(.relative(presentation: .named)))"
    }

    var accessibilityDescription: String {
        var parts = [title.isEmpty ? String(localized: "Untitled") : title, String(localized: "notebook"),
                     pageCount == 1 ? String(localized: "1 page") : String(localized: "\(pageCount) pages"),
                     String(localized: "edited \(modifiedAt.formatted(.relative(presentation: .named)))")]
        if isFavorite { parts.append(String(localized: "favourite")) }
        if let folder { parts.append(String(localized: "in \(folder.name)")) }
        if issueCount > 0 { parts.append(String(localized: "has files that couldn't be read")) }
        return parts.joined(separator: ", ")
    }
}
