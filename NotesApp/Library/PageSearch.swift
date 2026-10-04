import SwiftUI

struct PageHit: Identifiable, Hashable, Sendable {
    let notebookID: UUID
    let page: NotebookPage
    let index: Int
    let snippet: String
    /// Set when the match is in what was said in a recording: which recording, counting from one.
    var recording: Int?
    var id: String { "\(notebookID.uuidString)-\(page.id.uuidString)-\(recording ?? 0)" }

    /// "Page 3", or "Recording 2" for a match in a transcript.
    var place: String {
        recording.map { String(localized: "Recording \($0)") } ?? String(localized: "Page \(index + 1)")
    }

    func title(in notebook: String) -> String {
        recording.map { String(localized: "\(notebook), recording \($0)") } ?? String(localized: "\(notebook), page \(index + 1)")
    }

    /// What VoiceOver reads for the hit: where it is, then the words round the match.
    func label(in notebook: String) -> String {
        recording.map { String(localized: "\(notebook), recording \($0): \(snippet)") } ?? String(localized: "\(notebook), page \(index + 1): \(snippet)")
    }
}

/// Finds which pages of the matching notebooks contain the query, from each page's recognised text, and which
/// recordings from their transcripts. A recording's match opens the first page written on while it ran.
enum PageSearch {
    static func hits(for query: String, in ids: [UUID], root: StorageRoot, limitPerNotebook: Int = 8, limit: Int = 60) async -> [UUID: [PageHit]] {
        var result: [UUID: [PageHit]] = [:]
        var total = 0
        for id in ids {
            if Task.isCancelled || total >= limit { break }
            let package = NotebookPackage(root: root, id: id)
            guard let manifest = try? await package.readManifest().manifest else { continue }
            let pages = manifest.pages
            var hits: [PageHit] = []
            for (index, page) in pages.enumerated() where hits.count < limitPerNotebook && total + hits.count < limit {
                if Task.isCancelled { return result }
                guard let text = await package.readText(page.id), let snippet = snippet(in: text, for: query) else { continue }
                hits.append(PageHit(notebookID: id, page: page, index: index, snippet: snippet))
            }
            for (number, recording) in manifest.recordings.enumerated() where recording.transcriptFile != nil && hits.count < limitPerNotebook && total + hits.count < limit {
                guard let text = try? String(contentsOf: package.transcriptTextURL(recording.id), encoding: .utf8),
                      let snippet = snippet(in: text, for: query) else { continue }
                let index = recording.inkedPages?.compactMap { id in pages.firstIndex { $0.id == id } }.min() ?? 0
                guard pages.indices.contains(index) else { continue }
                hits.append(PageHit(notebookID: id, page: pages[index], index: index, snippet: snippet, recording: number + 1))
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

    /// Mustard under ink at night; on light paper the audit reads a pale band as faint text, so it deepens to ochre under cream.
    private static let highlighter = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? .mustard : UIColor(hex: 0x806113) })
    private static let onHighlighter = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? .onMustard : .labelCream })

    /// The snippet with every match in bold on a mustard band, so a match never relies on colour alone.
    static func highlighted(_ snippet: String, query: String) -> AttributedString {
        var text = AttributedString(snippet)
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return text }
        var remaining = snippet.startIndex..<snippet.endIndex
        while let match = snippet.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive], range: remaining) {
            if let range = Range(match, in: text) {
                text[range].backgroundColor = highlighter
                text[range].foregroundColor = onHighlighter
                text[range].font = .subheadline.bold()
            }
            remaining = match.upperBound..<snippet.endIndex
        }
        return text
    }
}

/// "Pages" results under the matching notebooks: each hit shows its page and the text around the match.
struct PageHitsSection: View {
    let records: [NotebookRecord]
    let hits: [UUID: [PageHit]]
    let query: String
    let zoomNamespace: Namespace.ID
    let onOpen: (NotebookRecord, UUID, String) -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: Space.x5) {
            ShelfLabel(title: String(localized: "Pages"))
            ForEach(records.filter { hits[$0.id] != nil }) { record in
                VStack(alignment: .leading, spacing: Space.x2) {
                    Text(record.title).font(.headline).foregroundStyle(Color.ink)
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: Space.x4) {
                            ForEach(hits[record.id] ?? []) { hit in
                                PageHitCard(hit: hit, query: query, zoomNamespace: zoomNamespace) { onOpen(record, hit.page.id, "hit-\(hit.id)") }
                                    .accessibilityLabel(Text(hit.label(in: record.title)))
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
    let query: String
    let zoomNamespace: Namespace.ID
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
                .aspectRatio(hit.page.shownSize.width / max(hit.page.shownSize.height, 1), contentMode: .fit)
                .frame(width: 56)
                .overlay { Rectangle().strokeBorder(Color.hairline, lineWidth: 1) }
                VStack(alignment: .leading, spacing: Space.x1) {
                    Text(hit.place).metaStyle(.caption)
                    Text(PageSearch.highlighted(hit.snippet, query: query))
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
            .zoomSource(id: "hit-\(hit.id)", in: zoomNamespace)
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
