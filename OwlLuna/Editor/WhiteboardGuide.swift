import SwiftUI

/// Shown under the whiteboard's bar until it is put away once: what a whiteboard is, in two lines.
struct WhiteboardTip: View {
    let showGuide: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            HStack(alignment: .top, spacing: Space.x3) {
                Image(systemName: "scribble.variable")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.x1) {
                    Text("This page has no edges.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.ink)
                    Text("Write in any direction. Drag with two fingers to move, and pinch to zoom.")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
            }
            HStack(spacing: Space.x2) {
                Spacer(minLength: 0)
                Button("What the Buttons Do", action: showGuide)
                    .buttonStyle(.owlLuna(.secondary, compact: true))
                    .accessibilityIdentifier("editor.board.tip.guide")
                Button("Got It", action: dismiss)
                    .buttonStyle(.owlLuna(.primary, compact: true))
                    .accessibilityIdentifier("editor.board.tip.done")
            }
        }
        .padding(Space.x4)
        .frame(maxWidth: 420, alignment: .leading)
        .board(in: RoundedRectangle.bar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("editor.board.tip")
    }
}

/// Every button round an open whiteboard, with its name and what it does.
struct WhiteboardGuide: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.panelClose) private var panelClose

    private struct Entry: Identifiable {
        let symbol: String
        let title: String
        let detail: String
        var id: String { title }
    }

    private var moving: [Entry] {
        [Entry(symbol: "hand.draw", title: String(localized: "Move"),
               detail: String(localized: "Drag with two fingers. If only Apple Pencil draws, one finger moves the whiteboard too.")),
         Entry(symbol: "plus.magnifyingglass", title: String(localized: "Zoom"),
               detail: String(localized: "Pinch to step back and see more, or to come closer and write small."))]
    }

    private var board: [Entry] {
        [Entry(symbol: "scribble.variable", title: String(localized: "Whiteboard"),
               detail: String(localized: "At the top while a whiteboard is open. It holds the three below, and this guide.")),
         Entry(symbol: "arrow.up.left.and.arrow.down.right", title: String(localized: "Show Everything"),
               detail: String(localized: "Steps back until everything on the whiteboard is in view.")),
         Entry(symbol: "1.magnifyingglass", title: String(localized: "Actual Size"),
               detail: String(localized: "Returns to writing size, where you are looking.")),
         Entry(symbol: "rectangle.stack", title: String(localized: "Pages"),
               detail: String(localized: "Every page of the notebook. Among them a whiteboard is a card: tap the card to open it again."))]
    }

    private var top: [Entry] {
        [Entry(symbol: "chevron.backward", title: String(localized: "Library"),
               detail: String(localized: "Saves the notebook and goes back to your shelves.")),
         Entry(symbol: "arrow.uturn.backward", title: String(localized: "Undo and Redo"),
               detail: String(localized: "Takes back the last thing you did, or does it again.")),
         Entry(symbol: "plus", title: String(localized: "Add"),
               detail: String(localized: "A page, another whiteboard, a picture, a text box, a sticker or a link.")),
         Entry(symbol: "mic", title: String(localized: "Record Audio"),
               detail: String(localized: "Records sound while you write, to play back along with your ink.")),
         Entry(symbol: "waveform", title: String(localized: "Recordings"),
               detail: String(localized: "What has been recorded in this notebook.")),
         Entry(symbol: "pencil.tip.crop.circle", title: String(localized: "Tools"),
               detail: String(localized: "Shows or hides the tray of tools at the bottom.")),
         Entry(symbol: "ellipsis.circle", title: String(localized: "More"),
               detail: String(localized: "Change the paper, find words, make flashcards, present, and choose what draws.")),
         Entry(symbol: "bookmark", title: String(localized: "Bookmark"),
               detail: String(localized: "Marks this page so it is easy to come back to.")),
         Entry(symbol: "number", title: String(localized: "Page Number"),
               detail: String(localized: "Shows every page. Touch and hold it to go to a page by its number."))]
    }

    private var tray: [Entry] {
        [Entry(symbol: "pencil.tip", title: String(localized: "Pens"),
               detail: String(localized: "Tap a pen to write with it. Tap it again to change its kind, colour and width.")),
         Entry(symbol: "plus", title: String(localized: "New Pen"),
               detail: String(localized: "Adds a pen like the one in hand, in another colour.")),
         Entry(symbol: "eraser", title: String(localized: "Eraser"),
               detail: String(localized: "Takes whole strokes, or part of one. Tap it again to choose.")),
         Entry(symbol: "lasso", title: String(localized: "Lasso"),
               detail: String(localized: "Draw round ink, then drag it somewhere else.")),
         Entry(symbol: "slider.horizontal.3", title: String(localized: "Customise Tools"),
               detail: String(localized: "Chooses the shortcuts that stand beside the tools, like Picture and Text Box."))]
    }

    var body: some View {
        VStack(spacing: 0) {
            if panelClose == nil {
                HStack(spacing: Space.x3) {
                    Text("Whiteboard Guide")
                        .displayFont(22, relativeTo: .title3)
                        .foregroundStyle(Color.ink)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    Button("Done") { dismiss() }
                        .buttonStyle(.owlLuna(.primary, compact: true))
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("editor.board.guide.done")
                }
                .padding(.horizontal, Space.x5)
                .padding(.top, Space.x4)
                .padding(.bottom, Space.x2)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: Space.x5) {
                    Text("A whiteboard is a page with no edges. Write in any direction and it keeps going.")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    section("Moving Around", moving)
                    section("The Whiteboard Button", board)
                    section("At the Top", top)
                    section("At the Bottom", tray)
                }
                .padding(.horizontal, Space.x5)
                .padding(.top, Space.x2)
                .padding(.bottom, Space.x6)
            }
        }
        .frame(minWidth: 320, idealWidth: 400, minHeight: 320, idealHeight: 640)
        .background(Color.surface)
    }

    private func section(_ title: LocalizedStringKey, _ entries: [Entry]) -> some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            Text(title).metaStyle(.footnote).accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(entries) { entry in
                    if entry.id != entries.first?.id { Rectangle().fill(Color.hairline).frame(height: 1).padding(.leading, 60) }
                    HStack(alignment: .top, spacing: Space.x3) {
                        Image(systemName: entry.symbol)
                            .font(.body.weight(.medium))
                            .foregroundStyle(Color.ink)
                            .frame(width: 36, height: 36)
                            .well(in: RoundedRectangle.plate)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.ink)
                            Text(entry.detail).font(.footnote).foregroundStyle(Color.textSecondary)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(Space.x3)
                    .accessibilityElement(children: .combine)
                }
            }
            .background(Color.paper, in: RoundedRectangle.plate)
            .overlay { RoundedRectangle.plate.strokeBorder(Color.hairline) }
        }
    }
}
