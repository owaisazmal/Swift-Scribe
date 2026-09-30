import SwiftUI

struct PageHit: Identifiable, Hashable, Sendable {
    let notebookID: UUID
    let page: NotebookPage
    let index: Int
    let snippet: String
    var id: String { "\(notebookID.uuidString)-\(page.id.uuidString)" }
}

/// Finds which pages of the matching notebooks contain the query, from each page's recognised text.
enum PageSearch {
    static func hits(for query: String, in ids: [UUID], root: StorageRoot, limitPerNotebook: Int = 8, limit: Int = 60) async -> [UUID: [PageHit]] {
        var result: [UUID: [PageHit]] = [:]
        var total = 0
        for id in ids {
            if Task.isCancelled || total >= limit { break }
            let package = NotebookPackage(root: root, id: id)
            guard let pages = try? await package.readManifest().manifest.pages else { continue }
            var hits: [PageHit] = []
            for (index, page) in pages.enumerated() where hits.count < limitPerNotebook && total + hits.count < limit {
                if Task.isCancelled { return result }
                guard let text = await package.readText(page.id), let snippet = snippet(in: text, for: query) else { continue }
                hits.append(PageHit(notebookID: id, page: page, index: index, snippet: snippet))
            }
            if !hits.isEmpty { result[id] = hits }
            total += hits.count
        }
        return result
    }

    /// The text around the first match, on one line, without the "#ink:" header.
    static func snippet(in text: String, for query: String, radius: Int = 36) -> String? {
        let body = text.split(separator: "\n", omittingEmptySubsequences: false).filter { !$0.hasPrefix("#ink:") }.joined(separator: " ")
        guard let range = body.localizedStandardRange(of: query) else { return nil }
        let start = body.index(range.lowerBound, offsetBy: -radius, limitedBy: body.startIndex) ?? body.startIndex
        let end = body.index(range.upperBound, offsetBy: radius, limitedBy: body.endIndex) ?? body.endIndex
        let excerpt = body[start..<end].trimmingCharacters(in: .whitespacesAndNewlines)
        return (start > body.startIndex ? "…" : "") + excerpt + (end < body.endIndex ? "…" : "")
    }
}

/// "Pages" results under the matching notebooks: each hit shows its page and the text around the match.
struct PageHitsSection: View {
    let records: [NotebookRecord]
    let hits: [UUID: [PageHit]]
    let onOpen: (NotebookRecord, UUID) -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: Space.x5) {
            ShelfLabel(title: String(localized: "Pages"))
            ForEach(records.filter { hits[$0.id] != nil }) { record in
                VStack(alignment: .leading, spacing: Space.x2) {
                    Text(record.title).font(.headline).foregroundStyle(Color.ink)
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: Space.x4) {
                            ForEach(hits[record.id] ?? []) { hit in
                                PageHitCard(hit: hit) { onOpen(record, hit.page.id) }
                                    .accessibilityLabel(Text("\(record.title), page \(hit.index + 1): \(hit.snippet)"))
                                    .accessibilityHint(Text("Opens the notebook at this page"))
                            }
                        }
                        .padding(.vertical, Space.x1)
                    }
                }
            }
        }
    }
}

private struct PageHitCard: View {
    let hit: PageHit
    let action: () -> Void
    @Environment(LibraryStore.self) private var store
    @State private var image: UIImage?

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: Space.x3) {
                Group {
                    if let image {
                        Image(uiImage: image).resizable()
                    } else {
                        Rectangle().fill(Color(uiColor: PageRenderer.paperColor(hit.page.effectivePaperColor)))
                    }
                }
                .aspectRatio(hit.page.size.width / max(hit.page.size.height, 1), contentMode: .fit)
                .frame(width: 56)
                .overlay { Rectangle().strokeBorder(Color.hairline, lineWidth: 1) }
                VStack(alignment: .leading, spacing: Space.x1) {
                    Text("Page \(hit.index + 1)").metaStyle(.caption)
                    Text(hit.snippet)
                        .font(.subheadline)
                        .foregroundStyle(Color.ink)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                .frame(width: 200, alignment: .leading)
            }
            .padding(Space.x3)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.control))
            .overlay { RoundedRectangle(cornerRadius: Radius.control).strokeBorder(Color.hairline) }
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .task(id: hit.page.thumbnailKey) {
            image = await PageThumbnailer.thumbnail(package: NotebookPackage(root: store.root, id: hit.notebookID), page: hit.page)
        }
    }
}
